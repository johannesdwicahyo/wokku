# A 6-digit sign-in code mailed to an address (SignInCodes::Issue/Verify).
# Only HMAC-SHA256(secret_key_base, "email:code") is stored; a row that
# won't be mailed stores UNMATCHABLE so no guess can ever verify it. The
# plain code travels to the mailer only inside an encrypted, 10-minute
# token, so it never sits in the job queue or an error report.
class SignInCode < ApplicationRecord
  TTL = 10.minutes
  MAX_ATTEMPTS = 5
  RESEND_AFTER = 45.seconds
  UNMATCHABLE = "-" # secure_compare is false on any length mismatch
  TOKEN_PURPOSE = "sign_in_code"

  scope :unconsumed, -> { where(consumed_at: nil) }
  scope :locked, -> { where(attempts: MAX_ATTEMPTS..) }

  # NFKC folds look-alikes (fullwidth letters, NBSP) first; scrub keeps a
  # stray invalid byte from raising. Inner whitespace/invisibles are left
  # in for Issue to reject.
  def self.normalize(email)
    email.to_s.scrub("").unicode_normalize(:nfkc).gsub(/\A[[:space:]]+|[[:space:]]+\z/, "").downcase
  end

  def self.digest(email, code)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "#{email}:#{code}")
  end

  def self.encryptor
    ActiveSupport::MessageEncryptor.new(Rails.application.key_generator.generate_key("wokku sign-in code", 32))
  end

  def self.encrypt_code(code) = encryptor.encrypt_and_sign(code, expires_in: TTL, purpose: TOKEN_PURPOSE)

  # → the code, or nil when the token is expired, forged or missing.
  def self.decrypt_code(token)
    encryptor.decrypt_and_verify(token.to_s, purpose: TOKEN_PURPOSE)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def matches?(code)
    ActiveSupport::SecurityUtils.secure_compare(self.class.digest(email, code), code_digest)
  end
end
