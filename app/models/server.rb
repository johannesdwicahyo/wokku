class Server < ApplicationRecord
  belongs_to :team

  encrypts :ssh_private_key

  enum :status, { connected: 0, unreachable: 1, auth_failed: 2, syncing: 3 }

  has_many :app_records, dependent: :destroy
  has_many :database_services, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :team_id }
  validates :host, presence: true
  validates :port, numericality: { only_integer: true, greater_than: 0 }
end
