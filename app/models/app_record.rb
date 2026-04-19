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
  has_many :dyno_allocations, dependent: :destroy

  enum :status, { running: 0, stopped: 1, crashed: 2, deploying: 3, sleeping: 4, created: 5 }

  validates :name, presence: true,
    uniqueness: { scope: :server_id },
    format: { with: /\A[a-z][a-z0-9-]*\z/, message: "must be lowercase alphanumeric with hyphens" }
  validates :pr_number, uniqueness: { scope: :parent_app_id }, if: :is_preview?

  scope :stale, -> { where("synced_at < ? OR synced_at IS NULL", 5.minutes.ago) }
  scope :main_apps, -> { where(is_preview: false) }
  scope :previews, -> { where(is_preview: true) }

  # Canonical git remote URL shown to users everywhere (dashboard, API,
  # CLI). Goes through the wokku SSH gateway rather than exposing the
  # underlying Dokku server IP.
  def git_remote_url
    host = ENV.fetch("WOKKU_GIT_HOST", "wokku.cloud")
    "git@#{host}:#{name}"
  end

  # Direct-to-Dokku URL. Still works and can be used as a bypass if the
  # gateway is down. Kept separately so we can display it in admin
  # views if needed.
  def direct_git_remote_url
    "dokku@#{server.host}:#{name}"
  end

  def track_resource_usage!
    allocation = dyno_allocations.includes(:dyno_tier).find_by(process_type: "web")
    tier_name = allocation&.dyno_tier&.name || "eco"
    price = allocation&.dyno_tier&.price_cents_per_hour || 0

    existing = ResourceUsage.find_by(resource_id_ref: "AppRecord:#{id}", stopped_at: nil)
    return if existing

    ResourceUsage.create!(
      user_id: created_by_id,
      resource_type: "container",
      resource_id_ref: "AppRecord:#{id}",
      tier_name: tier_name,
      price_cents_per_hour: price,
      started_at: Time.current,
      metadata: { name: name, server: server.name }.to_json
    )
  end

  def stop_resource_usage!
    ResourceUsage.where(resource_id_ref: "AppRecord:#{id}", stopped_at: nil)
                 .find_each(&:stop!)
  end
end
