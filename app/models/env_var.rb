class EnvVar < ApplicationRecord
  belongs_to :app_record

  encrypts :value

  # Allow both uppercase (POSIX convention) AND lowercase-with-underscores
  # (some apps require it — e.g. Ghost's `database__client`, `database__connection__*`).
  # Still rejects shell-hostile names: leading digits, spaces, hyphens, etc.
  validates :key, presence: true, uniqueness: { scope: [ :app_record_id, :scope ] },
    format: { with: /\A[A-Za-z_][A-Za-z0-9_]*\z/, message: "must start with a letter or underscore and contain only letters, digits, and underscores" }

  # Trailing newlines from form paste used to slip through and break
  # Dokku's `config:set` — once the SSH command hit the host, the dokku
  # shell's line-based parsing chopped the single-quoted value in half
  # and xargs threw "unmatched single quote". Strip on save so the
  # rendered shell command stays single-line. Internal newlines (real
  # multi-line values like PEM keys) are preserved.
  before_validation :strip_trailing_newlines

  private

  def strip_trailing_newlines
    return unless value.is_a?(String)
    value.gsub!(/[\r\n]+\z/, "")
  end
end
