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

  def self.bucket_name_for(app) = "wk-#{app.id.delete('-')[-12..]}" # random tail: UUIDv7's head is the creation ms

  UNAVAILABLE = "Object storage is temporarily unavailable, try again shortly".freeze

  def not_ready_message = "Object storage is not ready (status: #{status})"

  def used_gb = used_bytes.to_f / 1024**3

  def near_quota? = used_gb >= quota_gb * WARN_AT

  # Free tier = the team's plan is Plan(free). Managed cloud overrides
  # Team#current_plan with the active subscription, so this follows billing.
  def free_team? = !!team.current_plan&.free?

  PRICE_IDR_PER_GB = 400

  # [http_status, message] when gb is not an acceptable new quota, else nil.
  def quota_error(gb)
    gb = Integer(gb.to_s, exception: false)
    return [ :unprocessable_entity, "quota_gb must be between 1 and #{MAX_QUOTA_GB} GB" ] unless gb&.between?(1, MAX_QUOTA_GB)
    [ :forbidden, "Free plan storage is fixed at #{FREE_QUOTA_GB} GB" ] if free_team? && gb != FREE_QUOTA_GB
  end

  # API/dashboard representation; the secret only travels when reveal is true.
  def as_api_json(reveal:)
    h = {
      bucket: name, endpoint: Wokku.config.object_storage&.dig(:endpoint),
      region: ObjectStorage::Provisioner::REGION, access_key_id: access_key,
      quota_gb: quota_gb, used_gb: used_gb.round(2), status: status,
      price_idr_per_gb: PRICE_IDR_PER_GB, free_gb: FREE_QUOTA_GB
    }
    h[:secret_access_key] = secret_key if reveal
    h
  end
end
