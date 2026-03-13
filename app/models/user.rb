class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum :role, { member: 0, admin: 1 }

  has_many :api_tokens, dependent: :destroy
  has_many :ssh_public_keys, dependent: :destroy
  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships
  has_many :subscriptions, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :usage_events, dependent: :destroy

  def current_plan
    subscriptions.current.includes(:plan).first&.plan || Plan.find_by(name: "free")
  end
end
