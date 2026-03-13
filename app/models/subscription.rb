class Subscription < ApplicationRecord
  belongs_to :user
  belongs_to :plan

  enum :status, { active: 0, past_due: 1, canceled: 2, trialing: 3 }

  validates :status, presence: true

  scope :current, -> { where(status: [:active, :trialing]) }
end
