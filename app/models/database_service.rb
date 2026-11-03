class DatabaseService < ApplicationRecord
  # Datastore engine catalogs (engine-owned since the P2 rider cleanup;
  # Plan aliases these for cloud back-compat). Which engines exist is
  # product; which a PLAN may use stays plan logic in the cloud.
  # memcached left the offering 2026-10-06: a shared memcached isolates
  # tenants by key prefix only (no auth), so any tenant can read or
  # flush_all everyone's keys. Last tenant + parent removed from prod
  # 2026-10-12, wokkud handler deleted.
  SHARED_ENGINES      = %w[postgres mariadb redis].freeze
  # Every shared engine is free on every plan (founder, 2026-10-05).
  SHARED_ENGINES_FREE = SHARED_ENGINES
  DEDICATED_ENGINES   = %w[postgres mysql mariadb mongodb redis].freeze
  belongs_to :server
  belongs_to :creator, class_name: "User", foreign_key: :creator_id, optional: true
  belongs_to :parent_service, class_name: "DatabaseService", optional: true
  has_many :child_services, class_name: "DatabaseService", foreign_key: :parent_service_id, dependent: :restrict_with_exception

  belongs_to :upgrade_source, class_name: "DatabaseService", foreign_key: :upgrade_source_id, optional: true
  has_one    :upgrade_target, class_name: "DatabaseService", foreign_key: :upgrade_source_id, dependent: :nullify

  has_many :app_databases, dependent: :destroy
  # Op history is meaningless once the service row is gone, and the FK
  # otherwise blocks destroy (B4 smoke 2026-07-17: first wokkud-managed
  # destroy hit PG::ForeignKeyViolation).
  has_many :service_ops, dependent: :delete_all
  has_many :backups, dependent: :destroy
  has_many :app_records, through: :app_databases
  has_many :stats_snapshots, class_name: "DatabaseStatsSnapshot", dependent: :destroy

  # Phase B4: control plane owns the connection string once wokkud manages
  # the service (one URL-wiring mechanism; plugin :link/:info both retire).
  encrypts :dsn

  enum :status, {
    running: 0, stopped: 1, creating: 2, error: 3,
    upgrading_provisioning: 4, upgrading_migrating: 5, upgrading_cutover: 6,
    upgrading_failed: 7, pending_destroy: 8
  }

  # Live-update the addon card via Turbo Stream when status flips, so
  # the optimistic UI on /dashboard/addons and the per-app Resources
  # page reflects provisioning → running (or → error) without the user
  # having to refresh. Quiet when creator_id is nil (legacy rows or
  # template-deployer rows that don't subscribe to a stream).
  after_update_commit  :broadcast_status_change, if: -> { saved_change_to_status? && creator_id.present? }
  after_create_commit  :broadcast_card_insert,    if: -> { creator_id.present? }
  after_destroy_commit :broadcast_card_remove,    if: -> { creator_id.present? }

  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  # CLI/API consumers pass the human name (e.g. batumas-postgres) more
  # often than the uuid. Mirror AppRecord.lookup! so /databases/:id
  # routes resolve either form.
  def self.lookup!(id_or_name)
    if id_or_name.to_s.match?(UUID_PATTERN)
      find(id_or_name)
    else
      find_by!(name: id_or_name)
    end
  end

  scope :shared_tenants, -> { where(shared: true) }
  scope :dedicated, -> { where(shared: false) }

  # Retired engines: no NEW dedicated services; existing ones keep running,
  # billing, and backing up. Guarded on :create so every entry point
  # (dashboard, API, MCP) is covered in one place. Empty since MySQL came back
  # 2026-11-03 (retired 07-09 for memory; wokkud now boots it trimmed).
  RETIRED_TYPES = %w[].freeze

  # Free / infra tiers never get a per-resource shape (mirrors the cloud's
  # Billing::ShapeBackfill::EXCLUDED_SERVICE_TIERS).
  UNSHAPED_TIERS = %w[mini shared_free shared_host].freeze

  validates :name, presence: true, uniqueness: { scope: :server_id }
  validates :service_type, presence: true, inclusion: {
    in: %w[postgres redis mysql mariadb mongodb memcached rabbitmq elasticsearch meilisearch clickhouse nats]
  }
  validate :shared_tenants_must_have_parent
  validate :service_type_not_retired, on: :create
  validate :shape_on_grid, if: -> { cpu.present? || memory_mb.present? }
  # Shape wins over tier: a legacy tier assignment that leaves an old shape
  # would be ignored, so re-size to the tier — builder on → the tier rounded
  # onto the grid (tier-only rows bill Rp0); builder off → shape cleared so
  # the tier governs. disk_gb never shrinks (ResizeService's grow-only floor).
  before_save :shape_from_tier, if: -> { will_save_change_to_tier_name? && tier_name.present? && !will_save_change_to_cpu? && !will_save_change_to_memory_mb? }

  def over_quota?
    over_quota_at.present?
  end

  # shared_free tier: take one final synchronous snapshot before teardown
  # so the user has a recovery file in R2 for the policy's retention
  # window (currently 30 days) even after they delete the service.
  # Paid tiers skip this — their scheduled BackupJob already covers them.
  # NOT a before_destroy hook: the managed-path export is an async wokkud op,
  # and an op row created inside the destroy transaction is invisible to the
  # agent (it claims committed pending ids) — it can only ever time out at
  # 300s and the snapshot never captures (proven live 2026-07-24; shared
  # tenants were additionally exported AFTER their DB was dropped).
  # DatabaseProvisioner.destroy! — the canonical destroy path — calls
  # farewell_snapshot! BEFORE any teardown, outside any transaction.

  # Database cost is bundled into the user's plan invoice under Phase 4.
  # The old ResourceUsage open/close/rotate helpers were removed in 1.8
  # along with the daily-debit rail.

  def shape
    Resources::Shape.new(cpu: cpu, memory_mb: memory_mb, disk_gb: disk_gb.to_i) if cpu.present? && memory_mb.present?
  end

  # Derived connection cap for a shape-driven service (spec 2026-09-24 §5.3)
  # — matches today's dedicated tier presets exactly (128MB→10, 256→20,
  # 512→40), capped at 500 so a huge shape doesn't blow past engine limits.
  def max_connections_for_shape = [ memory_mb.to_i * 10 / 128, 500 ].min

  # The team that pays for this service — the EARLIEST link (deterministic:
  # a service linked into a second team later must not flip who's billed,
  # or change which team's enforcer/allocations sees it, depending on
  # `app_records.first`'s undefined order — cloud P2 fix round 1), else
  # the creator's (personal) team for a not-yet-linked datastore (review
  # fix round 1: `app_records.first&.team` alone left unlinked services
  # invisible to the plan enforcer and team_allocations).
  def billing_team
    app_databases.order(:created_at).first&.app_record&.team || creator&.teams&.first
  end

  private

  def shape_from_tier
    shape = Resources::ApplyChange.service_shape_for_tier(service_type, tier_name) unless shared?
    self.cpu, self.memory_mb = shape&.cpu, shape&.memory_mb
    self.disk_gb = [ disk_gb.to_i, shape.disk_gb ].max if shape
  end

  def service_type_not_retired
    return unless RETIRED_TYPES.include?(service_type)

    errors.add(:service_type, "dedicated #{service_type} is retired — existing services keep running; use Postgres for new databases")
  end

  def shared_tenants_must_have_parent
    return unless shared?
    errors.add(:parent_service_id, "required for shared tenants") if parent_service_id.blank?
  end

  def shape_on_grid
    Resources::Shape.new(cpu: cpu, memory_mb: memory_mb, disk_gb: disk_gb.to_i).errors.each { |e| errors.add(:base, e) }
  end

  public

  def service_tier
    @service_tier ||= ServiceTier.find_by(name: tier_name || "basic", service_type: service_type)
  end

  # Phase B4 cross-boundary contract: the exact container name wokkud execs
  # every op against for this row (op.service on the wire, set by
  # ServiceOpsController#claim). MUST match the string every DSN-composing
  # site already builds —
  # DatabaseProvisioner/CreateDedicatedDatabaseJob's #compose_dsn — and the
  # shared-postgres plugin's fixed parent container (wokkud's
  # sharedPostgresContainer const). Bare #name is never it: wokkud's
  # serviceTypeFromContainerName parses "dokku.<type>.<name>", not "<name>".
  # The database INSIDE a dedicated container is the service name with
  # underscores — dokku plugin convention, mirrored by every provisioning
  # path (verified across all adopted containers 2026-07-19). The row's
  # name keeps its hyphens.
  def dedicated_db_name = name.tr("-", "_")

  # The bind-mount data dir DatabaseProvisioner#provision_dedicated_via_ops!
  # creates (volume_path) — the key wokkud's volume_usage heartbeat reports
  # this dedicated service under.
  def data_dir = "/var/lib/dokku/services/#{service_type}/#{name}/data"

  # GB from the wokkud heartbeat's hourly volume_usage (Task 9). nil = no
  # telemetry yet — never guess.
  def disk_used_gb
    bytes = server&.vitals&.dig("volume_usage", data_dir)
    bytes && (bytes / 1024.0**3).round(2)
  end

  def container_name
    return parent_service.container_name if shared?
    # Shared-host parents are named after their container (dokku-shared-<engine>).
    # NOT the SHARED_PG_NETWORK constant: that pinned every engine's parent to
    # the postgres container (shared-host parent bug family #4 — B5a adopt
    # attached batumas' shared-memcached to the wrong container).
    return name if tier_name == "shared_host"
    "dokku.#{service_type}.#{name}"
  end

  def backup_policy
    # Fall back by tier NAME before assuming "basic": seeds only create a
    # shared_free ServiceTier row for postgres, so a shared redis/memcached
    # tenant without its row must still get the shared_free (no-auto-backup)
    # policy — the basic fallback would nightly-export a tenant that isn't a
    # dokku service and fail forever.
    service_tier&.backup_policy ||
      ServiceTier::BACKUP_POLICIES[tier_name] ||
      ServiceTier::BACKUP_POLICIES["basic"]
  end

  def auto_backup?
    backup_policy[:auto_backup]
  end

  # Shared redis tenants are never backed up (2026-10-12): the export is the
  # whole parent's RDB — every tenant's keys — and redis restore isn't
  # streamable anyway. Dedicated redis keeps its nightly export.
  BACKUPS_UNSUPPORTED_MESSAGE = "Shared Redis isn't backed up. Upgrade to a dedicated Redis for backups."

  def backups_unsupported?
    shared? && service_type == "redis"
  end

  def backup_limit_reached?
    cap = backup_policy[:free_cap]
    return false unless cap # paid tiers have no cap
    backups.completed.count >= cap
  end

  # Best-effort pre-destroy snapshot (shared_free policy). Called by
  # DatabaseProvisioner.destroy! BEFORE any teardown, OUTSIDE any transaction
  # — the managed export is an async wokkud op that must be committed to be
  # claimable, and the data must still exist to be exported.
  def farewell_snapshot!
    return unless backup_policy[:on_destroy_snapshot]
    return if backups_unsupported?
    return unless BackupSchedulerJob::BACKUPABLE_TYPES.include?(service_type)
    return unless server&.backup_destination&.enabled?

    farewell_started = Time.current
    backup = BackupService.new(self).perform!
    # The snapshot must OUTLIVE the upcoming destroy: detached, it escapes
    # both the dependent: :destroy sweep and the FK that otherwise blocks
    # the DELETE (the 2026-07-23 self-block loop that broke sweeps AND
    # template rollbacks).
    backup.update!(database_service_id: nil)
  rescue Services::Ops::Failed, Services::Ops::Timeout => e
    delete_farewell_backups!(farewell_started)
    # BackupService is managed-path-only now: the export is a wokkud op, so
    # "orphan already gone on the host / agent unreachable" surfaces as a
    # failed or timed-out op, not an SSH error. Best-effort — log it, but
    # don't alert Sentry and never block the destroy the user/sweeper asked
    # for.
    Rails.logger.warn("DatabaseService#farewell_snapshot!: backup skipped for #{id} (#{name}): #{e.class}: #{e.message}")
  rescue StandardError => e
    delete_farewell_backups!(farewell_started)
    Rails.logger.warn("DatabaseService#farewell_snapshot! failed for #{id}: #{e.class}: #{e.message}")
    Sentry.capture_exception(e, extra: { database_service_id: id, name: name }) if defined?(Sentry)
    # Don't block the destroy — the user explicitly asked for it.
  end

  private

  # A failed farewell attempt leaves its half-made Backup row referencing
  # this service — it holds no restorable object, and left in place its FK
  # blocks the destroy. delete_all: no Backup callbacks needed for a row
  # that never completed.
  def delete_farewell_backups!(since)
    backups.where("created_at >= ?", since).delete_all if since
  end

  def addon_stream_name
    "user_#{creator_id}_addons"
  end

  public

  def broadcast_backup_toast(level:, message:)
    Turbo::StreamsChannel.broadcast_append_to(
      "database_#{id}_backups",
      target: "toasts",
      partial: "dashboard/shared/toast",
      locals: { id: "toast_#{SecureRandom.hex(6)}", level: level, message: message }
    )
  end

  private

  # The /dashboard/addons index renders rows via the addon_card partial,
  # so a partial-replace is enough to update them in place.
  def broadcast_status_change
    broadcast_replace_to addon_stream_name,
      target: ActionView::RecordIdentifier.dom_id(self),
      partial: "dashboard/databases/addon_card",
      locals: { addon: self }

    # Per-app settings tab — the SharedAddonCardComponent is rendered with
    # dom_id(db, :upgrade_panel) so it has a separate target from the
    # addons-index card and won't clobber it.
    app_records.each do |linked_app|
      broadcast_replace_to addon_stream_name,
        target: ActionView::RecordIdentifier.dom_id(self, :upgrade_panel),
        renderable: Organisms::App::SharedAddonCardComponent.new(app: linked_app, database_service: self)
    end

    # The per-app Resources page has its own row layout (price, Remove
    # button) that we don't want clobbered by the partial. Send a
    # whole-page refresh stream alongside the replace; Turbo only fires
    # it on subscribers of that page (the addons index isn't subscribed
    # to the refresh channel).
    broadcast_refresh_later_to "#{addon_stream_name}_refresh"
  end

  def broadcast_card_insert
    broadcast_prepend_to addon_stream_name,
      target: "addon_cards",
      partial: "dashboard/databases/addon_card",
      locals: { addon: self }
    broadcast_refresh_later_to "#{addon_stream_name}_refresh"
  end

  def broadcast_card_remove
    broadcast_remove_to addon_stream_name,
      target: ActionView::RecordIdentifier.dom_id(self)
    broadcast_refresh_later_to "#{addon_stream_name}_refresh"
  end
end
