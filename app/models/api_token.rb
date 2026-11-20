class ApiToken < ApplicationRecord
  belongs_to :user
  has_many :device_tokens, dependent: :nullify

  validates :token_digest, presence: true, uniqueness: true
  validates :name, presence: true
  # F-02: a read token can only look (GET/HEAD) and sees secrets masked, like
  # a team viewer. Logins (CLI, apps, device flow) mint full tokens.
  SCOPES = %w[read full].freeze
  validates :scope, inclusion: { in: SCOPES }

  DEFAULT_TTL = 90.days

  scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def self.generate_token
    SecureRandom.hex(32)
  end

  def self.find_by_token(plain_token)
    return nil if plain_token.blank?
    find_by(token_digest: Digest::SHA256.hexdigest(plain_token))
  end

  def self.create_with_token!(attributes = {})
    plain_token = generate_token
    token = create!(attributes.merge(token_digest: Digest::SHA256.hexdigest(plain_token)))
    [ token, plain_token ]
  end

  # Expiry for a hand-made token: blank → 90 days, "never" → nil, else a
  # date/time. Raises ArgumentError when it can't be parsed.
  def self.expiry_from(value)
    return DEFAULT_TTL.from_now if value.blank?
    return nil if value.to_s == "never"

    Time.zone.parse(value.to_s) || raise(ArgumentError, "unparseable expiry")
  end

  def read_only?
    scope == "read"
  end

  def revoke!
    transaction do
      update!(revoked_at: Time.current)
      # A revoked token must stop pushing to the phone it registered (destroy: push_tickets FK).
      device_tokens.destroy_all
    end
  end

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def active?
    !revoked? && !expired?
  end

  def touch_last_used!
    update_column(:last_used_at, Time.current)
  end
end
