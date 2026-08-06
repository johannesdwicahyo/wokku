class DevSession < ApplicationRecord
  belongs_to :user
  belongs_to :app_record

  scope :active, -> {
    where(revoked_at: nil).where("expires_at > ?", Time.current)
  }

  def active?
    revoked_at.nil? && expires_at > Time.current
  end
end
