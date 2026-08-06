class PushTicket < ApplicationRecord
  belongs_to :device_token

  validates :ticket_id, presence: true, uniqueness: true

  scope :pending, -> { where(checked_at: nil) }
  scope :stale, -> { where(created_at: ...24.hours.ago) }
end
