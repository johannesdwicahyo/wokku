class DatabaseService < ApplicationRecord
  belongs_to :server
  belongs_to :creator, class_name: "User", foreign_key: :creator_id, optional: true
  belongs_to :parent_service, class_name: "DatabaseService", optional: true
  has_many :child_services, class_name: "DatabaseService", foreign_key: :parent_service_id, dependent: :restrict_with_exception

  belongs_to :upgrade_source, class_name: "DatabaseService", foreign_key: :upgrade_source_id, optional: true
  has_one    :upgrade_target, class_name: "DatabaseService", foreign_key: :upgrade_source_id, dependent: :nullify

  has_many :app_databases, dependent: :destroy
  has_many :backups, dependent: :destroy
  has_many :app_records, through: :app_databases
  has_many :stats_snapshots, class_name: "DatabaseStatsSnapshot", dependent: :destroy

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

  validates :name, presence: true, uniqueness: { scope: :server_id }
  validates :service_type, presence: true, inclusion: {
    in: %w[postgres redis mysql mongodb memcached rabbitmq elasticsearch meilisearch clickhouse nats]
  }
  validate :shared_tenants_must_have_parent

  def over_quota?
    over_quota_at.present?
  end

  # shared_free tier: take one final synchronous snapshot before teardown
  # so the user has a recovery file in R2 for the policy's retention
  # window (currently 30 days) even after they delete the service.
  # Paid tiers skip this — their scheduled BackupJob already covers them.
  before_destroy :snapshot_before_destroy_if_shared_free

  # Database cost is bundled into the user's plan invoice under Phase 4.
  # The old ResourceUsage open/close/rotate helpers were removed in 1.8
  # along with the daily-debit rail.

  private

  def shared_tenants_must_have_parent
    return unless shared?
    errors.add(:parent_service_id, "required for shared tenants") if parent_service_id.blank?
  end

  public

  def service_tier
    @service_tier ||= ServiceTier.find_by(name: tier_name || "basic", service_type: service_type)
  end

  def backup_policy
    service_tier&.backup_policy || ServiceTier::BACKUP_POLICIES["basic"]
  end

  def auto_backup?
    backup_policy[:auto_backup]
  end

  def backup_limit_reached?
    cap = backup_policy[:free_cap]
    return false unless cap # paid tiers have no cap
    backups.completed.count >= cap
  end

  private

  def snapshot_before_destroy_if_shared_free
    return unless backup_policy[:on_destroy_snapshot]
    return unless BackupSchedulerJob::BACKUPABLE_TYPES.include?(service_type)
    return unless server&.backup_destination&.enabled?

    BackupService.new(self).perform!
  rescue StandardError => e
    Rails.logger.warn("DatabaseService#snapshot_before_destroy_if_shared_free failed for #{id}: #{e.class}: #{e.message}")
    Sentry.capture_exception(e, extra: { database_service_id: id, name: name }) if defined?(Sentry)
    # Don't block the destroy — the user explicitly asked for it.
  end

  public

  private

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
