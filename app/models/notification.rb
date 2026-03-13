class Notification < ApplicationRecord
  belongs_to :team
  belongs_to :app_record, optional: true

  enum :channel, { email: 0, slack: 1, webhook: 2 }

  validates :channel, presence: true
  validates :events, presence: true
end
