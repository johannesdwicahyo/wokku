class SshPublicKey < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :public_key, presence: true, uniqueness: true
  validates :fingerprint, presence: true, uniqueness: true

  before_validation :compute_fingerprint, if: -> { public_key.present? && fingerprint.blank? }

  private

  def compute_fingerprint
    key = Net::SSH::KeyFactory.load_data_public_key(public_key)
    self.fingerprint = OpenSSL::Digest::SHA256.hexdigest(key.to_blob)
  rescue StandardError
    errors.add(:public_key, "is not a valid SSH public key")
  end
end
