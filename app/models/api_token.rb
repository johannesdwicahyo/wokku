class ApiToken < ApplicationRecord
  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :name, presence: true

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
    [token, plain_token]
  end

  def revoke!
    update!(revoked_at: Time.current)
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
