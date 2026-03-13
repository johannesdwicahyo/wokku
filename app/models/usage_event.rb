class UsageEvent < ApplicationRecord
  belongs_to :user
  belongs_to :app_record, optional: true

  validates :event_type, presence: true
end
