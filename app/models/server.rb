class Server < ApplicationRecord
  # Servers are platform infrastructure. Only system admins add them; any
  # signed-in user can deploy apps to them. team_id is retained for audit
  # (which admin added it) but isn't used for access control anymore.
  belongs_to :team, optional: true

  encrypts :ssh_private_key

  enum :status, { connected: 0, unreachable: 1, auth_failed: 2, syncing: 3 }

  has_many :app_records, dependent: :destroy
  has_many :database_services, dependent: :destroy
  has_one :backup_destination, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :host, presence: true
  validates :port, numericality: { only_integer: true, greater_than: 0 }

  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  # CLI/API consumers pass server names (jkt-01) more than UUIDs.
  # Mirror AppRecord.lookup! / DatabaseService.lookup!.
  def self.lookup!(id_or_name)
    if id_or_name.to_s.match?(UUID_PATTERN)
      find(id_or_name)
    else
      find_by!(name: id_or_name)
    end
  end

  # Install the wokku gateway's pubkey so `ssh dokku@<host>` from the
  # gateway is accepted, and record the host's SSH key fingerprint for
  # strict host-key verification. Both jobs are no-ops in environments
  # that haven't configured the gateway paths.
  after_create_commit  :install_gateway_key
  after_create_commit  :seed_known_hosts
  after_create_commit  :ensure_platform_backup_destination
  after_destroy_commit :remove_from_known_hosts

  # Creates a wokku-managed BackupDestination pointing at our central R2
  # bucket, so every server gets tenant-DB auto-backups out of the box.
  # Idempotent: does nothing if the server already has a destination or if
  # the platform backup env vars aren't configured (dev/test).
  def ensure_platform_backup_destination
    return if backup_destination.present?
    %w[
      WOKKU_TENANT_BACKUP_S3_BUCKET
      WOKKU_TENANT_BACKUP_S3_ENDPOINT
      WOKKU_TENANT_BACKUP_S3_ACCESS_KEY_ID
      WOKKU_TENANT_BACKUP_S3_SECRET_ACCESS_KEY
    ].each { |v| return if ENV[v].to_s.empty? }

    create_backup_destination!(
      enabled: true,
      provider: "r2",
      bucket: ENV.fetch("WOKKU_TENANT_BACKUP_S3_BUCKET"),
      endpoint_url: ENV.fetch("WOKKU_TENANT_BACKUP_S3_ENDPOINT"),
      region: ENV.fetch("WOKKU_TENANT_BACKUP_S3_REGION", "auto"),
      access_key_id: ENV.fetch("WOKKU_TENANT_BACKUP_S3_ACCESS_KEY_ID"),
      secret_access_key: ENV.fetch("WOKKU_TENANT_BACKUP_S3_SECRET_ACCESS_KEY"),
      path_prefix: "dbs/#{name}",
      retention_days: 30
    )
  rescue StandardError => e
    Rails.logger.warn("Failed to seed BackupDestination for server #{name}: #{e.class}: #{e.message}")
  end


  # Sum of allocated dyno memory (count * tier.memory_mb) across all apps
  # on this server. Used for capacity dashboards.
  def allocated_memory_mb
    DynoAllocation
      .joins(:dyno_tier, :app_record)
      .where(app_records: { server_id: id })
      .sum("dyno_allocations.count * dyno_tiers.memory_mb")
      .to_i
  end

  def capacity_total_mb_or_nil
    capacity_total_mb.to_i.positive? ? capacity_total_mb : nil
  end

  def capacity_pct
    total = capacity_total_mb_or_nil
    return nil if total.nil?
    ((allocated_memory_mb.to_f / total) * 100).round(1)
  end

  # Live host load (% of total RAM in use across all containers).
  # Populated by MetricsPollJob every minute. Returns nil until we
  # have a successful poll.
  def live_mem_pct
    return nil unless live_mem_used_mb && live_mem_total_mb && live_mem_total_mb > 0
    ((live_mem_used_mb.to_f / live_mem_total_mb) * 100).round(1)
  end

  def live_metrics_fresh?
    live_metrics_at && live_metrics_at > 5.minutes.ago
  end

  private

  def install_gateway_key
    InstallGatewayKeyOnServerJob.perform_later(id)
  end

  def seed_known_hosts
    SeedKnownHostsJob.perform_later(id)
  end

  def remove_from_known_hosts
    # We can't use perform_later here — the record is already destroyed
    # by the time the job runs. Snapshot the identity into the job args.
    Git::KnownHostsWriter.remove(self) rescue nil
  end
end
