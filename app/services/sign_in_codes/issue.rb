module SignInCodes
  # Step 1 of email sign-in. Always answers :sent (or :cooldown) the same
  # way whether or not the address has an account, so the response never
  # tells an attacker which emails exist. A row is recorded either way, so
  # the 45 s cooldown behaves identically too; a row that won't be mailed
  # gets an unmatchable digest, so a lucky guess can't create the account
  # the guard (or closed registration) refused. Long-run guessing is
  # bounded by Rack::Attack's sign_in_code/verify/email/day.
  class Issue
    Result = Data.define(:status, :wait)
    SENT = Result.new(status: :sent, wait: 0)
    MAX_EMAIL_LENGTH = 254
    MAX_PER_WINDOW = 3

    def self.call(email:, ip:, locale:)
      email = SignInCode.normalize(email)
      return SENT unless valid_format?(email)

      last = SignInCode.where(email: email).order(created_at: :desc).first
      if last && (age = Time.current - last.created_at) < SignInCode::RESEND_AFTER
        return Result.new(status: :cooldown, wait: (SignInCode::RESEND_AFTER - age).ceil)
      end

      # At most 3 codes (dummies too, so it isn't an oracle) per 10 minutes,
      # whatever reached Rack::Attack's per-email key.
      recent = SignInCode.where(email: email).where("created_at > ?", SignInCode::TTL.ago).order(created_at: :desc).limit(MAX_PER_WINDOW).pluck(:created_at)
      if recent.size >= MAX_PER_WINDOW
        return Result.new(status: :cooldown, wait: (recent.last + SignInCode::TTL - Time.current).ceil)
      end

      user = User.find_by(email: email)
      may_sign_in = user ? may_sign_in?(user) : may_sign_up?(email, ip)
      deliver = may_sign_in
      code = format("%06d", SecureRandom.random_number(10**6)) if deliver

      SignInCode.transaction do
        SignInCode.unconsumed.where(email: email).update_all(consumed_at: Time.current)
        SignInCode.create!(email: email, ip: ip, expires_at: SignInCode::TTL.from_now,
                           code_digest: deliver ? SignInCode.digest(email, code) : SignInCode::UNMATCHABLE)
      end

      locale = user&.locale.presence || locale.to_s
      if deliver
        SignInCodeMailer.code(email: email, token: SignInCode.encrypt_code(code), locale: locale).deliver_later
      end
      SENT
    end

    # Anything still holding whitespace, a control or an invisible format
    # character (zero-width space, …) after normalising is not an address.
    def self.valid_format?(email)
      email.length <= MAX_EMAIL_LENGTH && email.match?(Devise.email_regexp) &&
        !email.match?(/[[:space:][:cntrl:]\p{Cf}]/)
    end

    # An existing account takes a code only when its email came from a
    # provider (or a code): a self-edited email may be a planted victim
    # address, so it must never receive or accept a code (from_apple rule).
    def self.may_sign_in?(user)
      user.active_for_authentication? && user.email_provider_verified?
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
