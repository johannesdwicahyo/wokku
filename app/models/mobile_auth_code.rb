# One-time code for the iOS web sign-in handoff (/mobile/auth/start →
# wokku://auth?code=… → POST /api/v1/auth/mobile/token). Only the SHA-256
# of the code is stored; PKCE (S256) binds it to the app that started the
# flow, so an app that intercepts the wokku:// link cannot redeem it.
class MobileAuthCode < ApplicationRecord
  TTL = 2.minutes

  belongs_to :user

  def self.digest(code) = Digest::SHA256.hexdigest(code.to_s)

  def self.issue!(user:, code_challenge:)
    code = SecureRandom.urlsafe_base64(32)
    create!(user: user, code_challenge: code_challenge, code_digest: digest(code), expires_at: TTL.from_now)
    code
  end

  # → User on success (and the code is spent), nil otherwise. Callers must
  # not tell the client which check failed.
  def self.redeem(code:, code_verifier:)
    # ponytail: opportunistic cleanup; move to a recurring job if redemption volume ever matters
    where("created_at < ?", 1.day.ago).delete_all

    transaction do
      rec = lock.find_by(code_digest: digest(code))
      next nil unless rec && rec.used_at.nil? && rec.expires_at.future? && rec.verifier_matches?(code_verifier)

      rec.update!(used_at: Time.current)
      rec.user
    end
  end

  def verifier_matches?(verifier)
    expected = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier.to_s), padding: false)
    ActiveSupport::SecurityUtils.secure_compare(expected, code_challenge)
  end
end
