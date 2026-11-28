# A 6-digit sign-in code mailed to an address (SignInCodes::Issue/Verify).
# Only HMAC-SHA256(secret_key_base, "email:code") is stored; the plain
# code exists in the mail (and its queued delivery job) only.
class SignInCode < ApplicationRecord
  TTL = 10.minutes
  MAX_ATTEMPTS = 5
  RESEND_AFTER = 45.seconds

  scope :unconsumed, -> { where(consumed_at: nil) }

  def self.normalize(email) = email.to_s.strip.downcase

  def self.digest(email, code)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "#{email}:#{code}")
  end

  def matches?(code)
    ActiveSupport::SecurityUtils.secure_compare(self.class.digest(email, code), code_digest)
  end
end
