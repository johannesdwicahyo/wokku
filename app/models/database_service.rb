class DatabaseService < ApplicationRecord
  belongs_to :server
  belongs_to :creator, class_name: "User", foreign_key: :creator_id, optional: true
  belongs_to :parent_service, class_name: "DatabaseService", optional: true
  has_many :child_services, class_name: "DatabaseService", foreign_key: :parent_service_id, dependent: :restrict_with_exception

  has_many :app_databases, dependent: :destroy
  has_many :backups, dependent: :destroy
  has_many :app_records, through: :app_databases

  enum :status, { running: 0, stopped: 1, creating: 2, error: 3 }

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

  # Billing segments for dedicated paid addons. Free shared tenants and
  # tier=mini cache services skip this — they bill at 0¢/hr by definition.
  before_destroy :close_billing_segment

  def open_billing_segment(user:, app_record: app_records.first, at: Time.current)
    return if shared?
    rate = service_tier&.hourly_price_cents.to_f
    return if rate.zero?
    ResourceUsage.create!(
      user_id: user.id,
      resource_type: "database",
      resource_id_ref: "DatabaseService:#{id}",
      tier_name: tier_name,
      price_cents_per_hour: rate,
      started_at: at,
      metadata: { name: name, type: service_type, app: app_record&.name }
    )
  end

  def close_billing_segment(at: Time.current)
    ResourceUsage.where(resource_id_ref: "DatabaseService:#{id}", stopped_at: nil)
      .find_each { |u| u.stop!(at: at) }
  end

  def rotate_billing_segment(user:, at: Time.current)
    close_billing_segment(at: at)
    open_billing_segment(user: user, at: at)
  end

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
