class WildcardCertificate < ApplicationRecord
  encrypts :key_pem

  RENEW_WINDOW = 30.days

  def self.current
    where("expires_at > ?", Time.current).order(issued_at: :desc).first
  end

  def expiring?
    expires_at <= RENEW_WINDOW.from_now
  end
end
