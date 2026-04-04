class AppRecord < ApplicationRecord
  belongs_to :server
  belongs_to :team
  belongs_to :creator, class_name: "User", foreign_key: :created_by_id
  belongs_to :parent_app, class_name: "AppRecord", optional: true
  has_many :preview_apps, class_name: "AppRecord", foreign_key: :parent_app_id, dependent: :destroy

  has_many :releases, dependent: :destroy
  has_many :deploys, dependent: :destroy
  has_many :domains, dependent: :destroy
  has_many :env_vars, dependent: :destroy
  has_many :process_scales, dependent: :destroy
  has_many :app_databases, dependent: :destroy
  has_many :database_services, through: :app_databases
  has_many :metrics, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :log_drains, dependent: :destroy

  enum :status, { running: 0, stopped: 1, crashed: 2, deploying: 3, sleeping: 4 }

  validates :name, presence: true,
    uniqueness: { scope: :server_id },
    format: { with: /\A[a-z][a-z0-9-]*\z/, message: "must be lowercase alphanumeric with hyphens" }
  validates :pr_number, uniqueness: { scope: :parent_app_id }, if: :is_preview?

  scope :stale, -> { where("synced_at < ? OR synced_at IS NULL", 5.minutes.ago) }
  scope :main_apps, -> { where(is_preview: false) }
  scope :previews, -> { where(is_preview: true) }
end
