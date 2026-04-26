class SshPublicKey < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :public_key, presence: true
  validates :fingerprint, presence: true
  validate :fingerprint_unique_across_accounts

  before_validation :compute_fingerprint, if: -> { public_key.present? && fingerprint.blank? }

  after_create_commit :sync_key_to_servers
  after_destroy_commit :remove_key_from_servers
  after_commit :refresh_gateway_authorized_keys, on: [ :create, :destroy ]

  private

  def sync_key_to_servers
    SyncSshKeyJob.perform_later(id, user_id, action: :add)
  end

  def remove_key_from_servers
    SyncSshKeyJob.perform_later(id, user_id, action: :remove)
  end

  # Regenerate the gateway authorized_keys file on the host so this key
  # can (or can no longer) push to git@wokku.cloud. No-op in environments
  # that haven't configured a target path (dev/test).
  def refresh_gateway_authorized_keys
    UpdateGatewayAuthorizedKeysJob.perform_later
  end

  def compute_fingerprint
    key = Net::SSH::KeyFactory.load_data_public_key(public_key)
    self.fingerprint = OpenSSL::Digest::SHA256.hexdigest(key.to_blob)
  rescue StandardError
    errors.add(:public_key, "is not a valid SSH public key")
  end

  # Fingerprints must be unique platform-wide because the git gateway maps
  # a presenting SSH key to exactly one SshPublicKey row (and thus one
  # owner). Two accounts sharing a key would silently misroute pushes.
  #
  # Error messages are split so we can be helpful to the same user
  # re-uploading their own key, while not revealing that some OTHER
  # account owns a given key (which would be an enumeration vector —
  # SSH pubkeys are commonly public via GitHub /<user>.keys etc.).
  def fingerprint_unique_across_accounts
    return if fingerprint.blank?

    scope = self.class.where(fingerprint: fingerprint)
    scope = scope.where.not(id: id) if persisted?
    duplicate = scope.first
    return unless duplicate

    if duplicate.user_id == user_id
      errors.add(:base, "You've already added this key.")
    else
      errors.add(:base,
        "We couldn't add this key. If you manage multiple Wokku accounts " \
        "from the same machine, create a dedicated keypair for this account " \
        "and upload its .pub file. See /docs/apps/ssh-keys.")
    end
  end
end
