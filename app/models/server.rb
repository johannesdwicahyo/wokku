class Server < ApplicationRecord
  has_many :storage_backup_runs, dependent: :delete_all
  # All-wokkud world: new servers are born fully capability-flagged (the
  # DB defaults are false — Track-B gradual-rollout relics; existing rows
  # keep their values).
  attribute :wokkud_builds_enabled,   :boolean, default: true
  attribute :wokkud_router_enabled,   :boolean, default: true
  attribute :wokkud_services_enabled, :boolean, default: true
  attribute :wokkud_cron_enabled,     :boolean, default: true

  # Servers are platform infrastructure. Only system admins add them; any
  # signed-in user can deploy apps to them. team_id is retained for audit
  # (which admin added it) but isn't used for access control anymore.
  belongs_to :team, optional: true

  encrypts :ssh_private_key

  enum :status, { connected: 0, unreachable: 1, auth_failed: 2, syncing: 3 }

  has_many :app_records, dependent: :destroy
  has_many :database_services, dependent: :destroy
  has_many :logs, dependent: :destroy
  has_many :request_samples, dependent: :destroy
  has_many :incidents, dependent: :destroy
  has_many :lifecycle_ops, dependent: :destroy
  has_one :backup_destination, dependent: :destroy

  # Vector → wokku log ingest auth. Generated on first save if missing;
  # rotated by setting `ingest_token: nil; save!`.
  before_validation :ensure_ingest_token

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

  # --- wokkud host-agent heartbeat (Track A Phase 1) -----------------------
  HEARTBEAT_STATUSES  = %w[unknown ok degraded down].freeze
  HEARTBEAT_DOWN_AFTER = 60.seconds
  DEGRADED_DISK_PCT    = 90

  validates :heartbeat_status, inclusion: { in: HEARTBEAT_STATUSES }

  def agent_installed? = agent_version.present?

  def heartbeat_stale?
    heartbeat_at.nil? || heartbeat_at < HEARTBEAT_DOWN_AFTER.ago
  end

  # Called by Api::V1::Agent::HeartbeatsController on every beat. Uses
  # update_columns: beats arrive every 15s per host and must not run the
  # SSH-key callbacks/validations. Recovery email fires on ANY beat that
  # ends a down outage — down→ok AND down→degraded — so the founder's DOWN
  # page always gets closed, even if the host comes back impaired (e.g.
  # disk still >=90%). OpsMailer#host_recovered reads heartbeat_status
  # (already persisted by the update_columns above) to pick a status-aware
  # subject/body rather than sending a misleading all-clear for a degraded
  # return. The down transition itself is owned by HostHeartbeatMonitorJob
  # (absence of beats can't trigger model code).
  # Phase B5a: task keys persisted to app_records.live_containers — the
  # heartbeat's per-task shape minus the app name (that's the grouping key).
  LIVE_CONTAINER_KEYS = %w[process state desired_state started_at exit_code].freeze

  def record_heartbeat!(vitals:, agent_version: nil, tasks: nil)
    was_down = heartbeat_status == "down"
    status =
      if vitals["docker"] != "ok" || vitals["disk_used_pct"].to_f >= DEGRADED_DISK_PCT
        "degraded"
      else
        "ok"
      end
    update_columns(
      heartbeat_at: Time.current,
      vitals: vitals,
      agent_version: agent_version.presence || self.agent_version,
      heartbeat_status: status
    )
    if was_down
      begin
        Incident.open_for(self)&.resolve!
      rescue StandardError => e
        # Incident bookkeeping must never eat the recovery page.
        Rails.logger.warn("Server#record_heartbeat!: failed to resolve host incident for #{name}: #{e.message}")
        Sentry.capture_exception(e) if defined?(Sentry)
      end
      OpsMailer.host_recovered(self).deliver_later
    end

    # Phase B4: wokkud reports per-managed-service stats in the same beat
    # (replaces the Hosts::PostgresStats/RedisStats SSH path for managed
    # services — MetricsPollJob still covers unmanaged ones). A stats bug
    # must never fail the heartbeat itself, hence the rescue below is scoped
    # to only this loop.
    begin
      Array(vitals["services"]).each do |s|
        database_services.where(wokkud_managed: true, name: s["name"])
          .update_all(live_db_bytes: s["db_bytes"], live_mem_used_mb: s["mem_used_mb"], live_metrics_at: Time.current)
      end
    rescue StandardError => e
      Rails.logger.warn("record_heartbeat! service stats: #{e.class}: #{e.message}")
    end

    # Phase B5a: wokkud reports Swarm task states in the same beat; fan them
    # out per app to live_containers. Same contract as the stats block above:
    # a malformed payload or fan-out bug must NEVER break the beat itself.
    begin
      Array(tasks).select { |t| t.is_a?(Hash) && t["app"].present? }
                  .group_by { |t| t["app"] }
                  .each do |app_name, list|
        app = app_records.find_by(name: app_name)
        next unless app
        app.update_columns(
          live_containers: list.map { |t| t.slice(*LIVE_CONTAINER_KEYS) },
          live_containers_at: Time.current
        )
      end
      # wokkud reports only live tasks, so an app missing from a beat that
      # carried a task list has none (stopped / scaled to 0). Without this,
      # ps kept showing the last running tasks forever.
      if tasks.is_a?(Array)
        reported = tasks.filter_map { |t| t["app"] if t.is_a?(Hash) }
        app_records.where.not(name: reported).where("jsonb_array_length(COALESCE(live_containers, '[]'::jsonb)) > 0")
                   .update_all([ "live_containers = '[]'::jsonb, live_containers_at = ?", Time.current ])
      end
    rescue StandardError => e
      Rails.logger.warn("record_heartbeat! task fan-out: #{e.class}: #{e.message}")
    end

    # Wake-on-request: Caddy per-host request counters → last_request_at.
    # Same contract as the blocks above: never break the beat.
    begin
      Apps::VisitTracker.call(self, vitals["host_requests"])
    rescue StandardError => e
      Rails.logger.warn("record_heartbeat! visit tracking: #{e.class}: #{e.message}")
    end

    begin
      record_app_stats!(vitals["app_stats"])
    rescue StandardError => e
      Rails.logger.warn("record_heartbeat! app stats: #{e.class}: #{e.message}")
    end
  end

  # wokkud's per-Swarm-service docker stats ("wokku-<app>-<process>") →
  # live CPU/memory per app. Without this, hosts with no SSH metrics path
  # (self-host) showed 0 MB for every app. Longest app name wins so app
  # "foo" never absorbs "foo-bar"'s services.
  def record_app_stats!(stats)
    return unless stats.is_a?(Hash) && stats.any?

    apps = app_records.pluck(:id, :name).sort_by { |_, name| -name.length }
    totals = Hash.new { |h, k| h[k] = { cpu: 0.0, mem: 0, limit: 0 } }
    stats.each do |service, s|
      id, = apps.find { |_, name| service.to_s.start_with?("wokku-#{name}-") }
      next unless id && s.is_a?(Hash)
      t = totals[id]
      t[:cpu] += s["cpu_pct"].to_f
      t[:mem] += s["mem_mb"].to_i
      t[:limit] += s["mem_limit_mb"].to_i
    end
    now = Time.current
    totals.each do |id, t|
      AppRecord.where(id: id).update_all(live_cpu_pct: t[:cpu].round(1), live_mem_used_mb: t[:mem],
                                         live_mem_limit_mb: t[:limit], live_metrics_at: now)
    end
  end

  # Builds waiting for this host's wokkud to claim them (Phase 4c). The
  # heartbeat response carries these ids — wokkud is outbound-only, so the
  # 15s beat doubles as the job-pickup channel.
  def pending_build_deploys
    Deploy.joins(:app_record)
          .where(app_records: { server_id: id }, builder: "wokkud", build_picked_up_at: nil, status: :building)
  end

  # Phase B4: pending datastore ops for this host, oldest first so the
  # agent's single worker drains them in issue order.
  def pending_service_ops
    ServiceOp.where(server_id: id, status: :pending).order(:created_at)
  end

  # Track B Phase B5a: pending Swarm lifecycle ops for this host, oldest
  # first so the agent drains them in issue order (parity with
  # pending_service_ops).
  def pending_lifecycle_ops
    lifecycle_ops.pending.order(:created_at)
  end

  # Record the host's SSH key fingerprint for strict host-key
  # verification. No-op in environments without the gateway paths.
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

  def seed_known_hosts
    SeedKnownHostsJob.perform_later(id)
  end

  def remove_from_known_hosts
    # We can't use perform_later here — the record is already destroyed
    # by the time the job runs. Snapshot the identity into the job args.
    Git::KnownHostsWriter.remove(self) rescue nil
  end

  def ensure_ingest_token
    self.ingest_token ||= SecureRandom.hex(32)
  end
end
