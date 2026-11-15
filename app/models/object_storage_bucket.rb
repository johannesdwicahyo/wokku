class ObjectStorageBucket < ApplicationRecord
  DEFAULT_QUOTA_GB = 10
  FREE_QUOTA_GB = 1
  MAX_QUOTA_GB = 1024
  WARN_AT = 0.8
  STATUSES = %w[provisioning active failed deleting].freeze

  belongs_to :app_record, optional: true
  belongs_to :team

  encrypts :secret_key

  validates :name, :access_key, :secret_key, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :quota_gb, numericality: { only_integer: true, in: 1..MAX_QUOTA_GB }

  STATUSES.each { |s| define_method(:"#{s}?") { status == s } }

  def self.bucket_name_for(app) = "wk-#{app.id.delete('-')[0, 12]}"

  def used_gb = used_bytes.to_f / 1024**3

  def near_quota? = used_gb >= quota_gb * WARN_AT

  # Free tier = the team's plan is Plan(free). Managed cloud overrides
  # Team#current_plan with the active subscription, so this follows billing.
  def free_team? = !!team.current_plan&.free?
end
