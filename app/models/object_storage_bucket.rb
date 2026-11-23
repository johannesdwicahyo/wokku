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
  def free_team? = limits[:free]

  # Plan limits via the host app's seam (see Wokku::Providers), computed once
  # per instance so a request does not re-run the lambda.
  def limits = @limits ||= Wokku.config.object_storage_limits.call(team)

  # Largest quota THIS bucket may have, nil = no cap. A free team is always
  # capped (at FREE_QUOTA_GB unless the seam says otherwise).
  def quota_cap
    return (limits[:max_bucket_gb] || FREE_QUOTA_GB) if free_team?
    limits[:max_bucket_gb] unless limits[:free] # differs from free_team? only under the specs' free_team? stub
  end

  PRICE_IDR_PER_GB = 400

  FREE_TEAM_LIMIT_MESSAGE = "The free plan includes #{FREE_QUOTA_GB} GB of object storage per account, " \
                            "and another app already uses it. Upgrade to add storage to more apps.".freeze

  # The free GB is per team (billing nets it once per team); a free team's
  # bucket is fixed at that 1 GB, so it gets exactly one bucket. The seam's
  # max_buckets, when set, replaces that rule.
  def self.free_team_limit_reached?(team)
    probe = new(team: team)
    live = where(team: team).where.not(status: "deleting")
    max = probe.limits[:max_buckets]
    return live.count >= max if max
    probe.free_team? && live.exists?
  end

  def self.limit_message(team)
    max = new(team: team).limits[:max_buckets]
    return FREE_TEAM_LIMIT_MESSAGE unless max
    "Your plan includes #{max} object storage #{'bucket'.pluralize(max)}, and you have reached the limit. " \
      "Upgrade your plan to add more."
  end

  # [http_status, message] when gb is not an acceptable new quota, else nil.
  def quota_error(gb)
    gb = Integer(gb.to_s, exception: false)
    return [ :unprocessable_entity, "quota_gb must be between 1 and #{MAX_QUOTA_GB} GB" ] unless gb&.between?(1, MAX_QUOTA_GB)
    cap = quota_cap
    return unless cap && gb > cap
    [ :forbidden, free_team? ? "Free plan storage is fixed at #{FREE_QUOTA_GB} GB" : "Your plan allows up to #{cap} GB of object storage" ]
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
