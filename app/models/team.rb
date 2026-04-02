class Team < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :team_memberships, dependent: :destroy
  has_many :users, through: :team_memberships
  has_many :servers, dependent: :destroy
  has_many :app_records, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :cloud_credentials, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end
