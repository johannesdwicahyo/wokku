class SshPublicKey < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :public_key, presence: true, uniqueness: true
  validates :fingerprint, presence: true, uniqueness: true

  before_validation :compute_fingerprint, if: -> { public_key.present? && fingerprint.blank? }

  after_create_commit :sync_key_to_servers
  after_destroy_commit :remove_key_from_servers

  private

  def sync_key_to_servers
    SyncSshKeyJob.perform_later(id, user_id, action: :add)
  end

  def remove_key_from_servers
    SyncSshKeyJob.perform_later(id, user_id, action: :remove)
  end

  def compute_fingerprint
    key = Net::SSH::KeyFactory.load_data_public_key(public_key)
    self.fingerprint = OpenSSL::Digest::SHA256.hexdigest(key.to_blob)
  rescue StandardError
    errors.add(:public_key, "is not a valid SSH public key")
  end
end
