module SignInCodes
  # Step 1 of email sign-in. Always answers :sent (or :cooldown) the same
  # way whether or not the address has an account, so the response never
  # tells an attacker which emails exist. A code row is recorded either way
  # (an unknown address gets the digest of a code nobody is sent) so the
  # 45 s cooldown behaves identically too; mail goes out only when the
  # address may sign in.
  class Issue
    Result = Data.define(:status, :wait)
    SENT = Result.new(status: :sent, wait: 0)
    MAX_EMAIL_LENGTH = 254

    def self.call(email:, ip:, locale:)
      email = SignInCode.normalize(email)
      return SENT unless email.length <= MAX_EMAIL_LENGTH && email.match?(Devise.email_regexp)

      last = SignInCode.where(email: email).order(created_at: :desc).first
      if last && (age = Time.current - last.created_at) < SignInCode::RESEND_AFTER
        return Result.new(status: :cooldown, wait: (SignInCode::RESEND_AFTER - age).ceil)
      end

      user = User.find_by(email: email)
      deliver = user ? user.active_for_authentication? : may_sign_up?(email, ip)
      code = format("%06d", SecureRandom.random_number(10**6))

      SignInCode.transaction do
        SignInCode.unconsumed.where(email: email).update_all(consumed_at: Time.current)
        SignInCode.create!(email: email, code_digest: SignInCode.digest(email, code),
                           expires_at: SignInCode::TTL.from_now, ip: ip)
      end
      SignInCodeMailer.code(email: email, code: code, locale: user&.locale.presence || locale.to_s).deliver_later if deliver
      SENT
    end

    # Same rule as User.from_omniauth: the admin email is never created.
    # The guard runs only here (not again at Verify), so a counting guard
    # sees each sign-up attempt once.
    def self.may_sign_up?(email, ip)
      email != User::ADMIN_EMAIL && Wokku.config.open_registration &&
        Wokku.config.email_signup_guard.call(email: email, ip: ip).present?
    end
  end
end
