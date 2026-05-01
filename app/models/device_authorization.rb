class DeviceAuthorization < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :api_token, optional: true

  encrypts :plain_token_payload

  STATUSES = %w[pending approved denied].freeze
  EXPIRES_IN = 10.minutes
  POLL_INTERVAL = 5.seconds
  USER_CODE_ALPHABET = "BCDFGHJKLMNPQRSTVWXZ".chars.freeze

  validates :device_code, presence: true, uniqueness: true
  validates :user_code, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where("expires_at > ?", Time.current) }

  def self.start!
    create!(
      device_code: SecureRandom.hex(32),
      user_code: generate_user_code,
      expires_at: EXPIRES_IN.from_now
    )
  end

  def self.generate_user_code
    loop do
      code = "#{random_block}-#{random_block}"
      return code unless exists?(user_code: code)
    end
  end

  def self.random_block
    Array.new(4) { USER_CODE_ALPHABET.sample }.join
  end

  def expired?
    expires_at <= Time.current
  end

  def pending?
    status == "pending" && !expired?
  end

  def approved?
    status == "approved"
  end

  def denied?
    status == "denied"
  end

  def approve!(user)
    return false if expired? || status != "pending"
    transaction do
      token_record, plain_token = ApiToken.create_with_token!(
        user: user,
        name: "cli-#{Time.current.to_i}"
      )
      update!(
        user: user,
        api_token: token_record,
        status: "approved",
        plain_token_payload: plain_token
      )
    end
    true
  end

  def deny!
    return false if expired? || status != "pending"
    update!(status: "denied")
  end

  def consume_plain_token!
    token = plain_token_payload
    return nil if token.blank?
    update_column(:plain_token_payload, nil)
    token
  end

  def touch_polled!
    update_column(:last_polled_at, Time.current)
  end
end
