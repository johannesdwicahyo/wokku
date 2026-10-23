# Per-user silence for PUSH alerts only (email/Slack/webhook channels are
# team-wide and unaffected). NULL app_record = every app, NULL event =
# every event; a row with both NULL is refused — unregister the device.
class AlertMute < ApplicationRecord
  EVENTS = PushNotificationService::TITLES.keys.freeze

  belongs_to :user
  belongs_to :app_record, optional: true

  validates :event, inclusion: { in: EVENTS }, allow_nil: true
  validate :not_everything

  scope :active, -> { where(expires_at: nil).or(where(expires_at: Time.current..)) }

  # app_record nil = the event's app is unknown: only app-wide (NULL app)
  # mutes can match it.
  def self.muted?(user:, app_record:, event:)
    active.where(user: user, app_record_id: [ nil, app_record&.id ].uniq, event: [ nil, event ]).exists?
  end

  def as_api_json
    { id: id, app_id: app_record_id, app_name: app_record&.name, event: event, until: expires_at, created_at: created_at }
  end

  private

  def not_everything
    errors.add(:base, "mute an app and/or an event — to silence everything, unregister the device instead") if app_record_id.nil? && event.nil?
  end
end
