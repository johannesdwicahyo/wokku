class DeviceToken < ApplicationRecord
  # Deterministic so the unique-index lookup (find_or_initialize_by(token:))
  # still works — same plaintext → same ciphertext.
  encrypts :token, deterministic: true

  belongs_to :user
  has_many :push_tickets, dependent: :destroy

  validates :token, presence: true, uniqueness: true
  validates :platform, presence: true, inclusion: { in: %w[ios android] }
end
