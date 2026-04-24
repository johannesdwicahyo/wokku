class EnvVar < ApplicationRecord
  belongs_to :app_record

  encrypts :value

  # Allow both uppercase (POSIX convention) AND lowercase-with-underscores
  # (some apps require it — e.g. Ghost's `database__client`, `database__connection__*`).
  # Still rejects shell-hostile names: leading digits, spaces, hyphens, etc.
  validates :key, presence: true, uniqueness: { scope: :app_record_id },
    format: { with: /\A[A-Za-z_][A-Za-z0-9_]*\z/, message: "must start with a letter or underscore and contain only letters, digits, and underscores" }
end
