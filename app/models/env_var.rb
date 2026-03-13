class EnvVar < ApplicationRecord
  belongs_to :app_record

  encrypts :value

  validates :key, presence: true, uniqueness: { scope: :app_record_id },
    format: { with: /\A[A-Z_][A-Z0-9_]*\z/, message: "must be uppercase with underscores" }
end
