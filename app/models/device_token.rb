class DeviceToken < ApplicationRecord
  belongs_to :user
  has_many :push_tickets, dependent: :destroy

  validates :token, presence: true, uniqueness: true
  validates :platform, presence: true, inclusion: { in: %w[ios android] }
end
