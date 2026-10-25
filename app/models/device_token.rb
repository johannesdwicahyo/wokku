class DeviceToken < ApplicationRecord
  # Deterministic so the unique-index lookup (find_or_initialize_by(token:))
  # still works — same plaintext → same ciphertext.
  encrypts :token, deterministic: true

  belongs_to :user
  belongs_to :api_token, optional: true
  has_many :push_tickets, dependent: :destroy

  # nil api_token = registered before token-binding; still deliverable.
  scope :deliverable, -> { where(api_token_id: nil).or(where(api_token_id: ApiToken.active.select(:id))) }

  validates :token, presence: true, uniqueness: true
  validates :platform, presence: true, inclusion: { in: %w[ios android] }
  validates :provider, inclusion: { in: %w[expo apns] }
end
