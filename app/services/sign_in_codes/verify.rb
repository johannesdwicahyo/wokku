module SignInCodes
  # Step 2 of email sign-in. Checks the newest unconsumed code for the
  # email; each wrong code counts as an attempt and after 5 the code is
  # :locked (so the 6th try fails even with the right code). On a
  # match the code is consumed and the user found, or created under the
  # same rules (and with the same post-create effects) as OAuth sign-up.
  # The caller still signs in through sign_in_with_two_factor.
  #
  # An unknown/closed/inactive/unverified-email account answers :invalid, same as a wrong
  # code (no enumeration).
  class Verify
    Result = Data.define(:user, :error, :new_user) do
      def initialize(user: nil, error: nil, new_user: false) = super
    end

    def self.call(email:, code:, ip:)
      email = SignInCode.normalize(email)
      code = code.to_s.strip
      rec = SignInCode.unconsumed.where(email: email).order(created_at: :desc).first
      return Result.new(error: :invalid) unless rec

      # Row lock: parallel guesses can't share an attempt count. No early
      # return inside, so the attempt always commits.
      error = rec.with_lock do
        if rec.attempts >= SignInCode::MAX_ATTEMPTS then :locked
        elsif rec.consumed_at then :invalid # killed by a newer code meanwhile
        elsif rec.expires_at <= Time.current then :expired
        elsif code.match?(/\A\d{6}\z/) && rec.matches?(code)
          rec.update!(consumed_at: Time.current)
          nil
        else
          rec.increment!(:attempts) # wrong attempts only, so attempts >= 5 always means locked
          :invalid
        end
      end
      return Result.new(error: error) if error

      user, new_user = find_or_create(email)
      return Result.new(error: :invalid) unless user && Issue.may_sign_in?(user)

      # Same post-create effects as Users::OmniauthCallbacksController#finish_sign_in.
      _team, first_time = user.ensure_personal_team!
      OnboardingMailer.welcome(user).deliver_later rescue nil if first_time # never block sign-in (as OAuth)
      Result.new(user: user, new_user: new_user)
    end

    def self.find_or_create(email)
      # Admin email: only the seeded admin, never a new account (from_omniauth rule).
      return [ User.find_by(email: email, role: :admin), false ] if email == User::ADMIN_EMAIL
      if (user = User.find_by(email: email))
        return [ user, false ]
      end
      return [ nil, false ] unless Wokku.config.open_registration

      # Fields mirror from_omniauth's create; name is the email's local part.
      user = User.create(email: email, password: Devise.friendly_token[0, 20],
                         email_provider_verified: true, name: email.split("@").first, **request_locale)
      user.persisted? ? [ user, true ] : [ User.find_by(email: email), false ] # lost a create race
    rescue ActiveRecord::RecordNotUnique
      [ User.find_by(email: email), false ]
    end

    # The sign-in page's locale (Localizable), or the column default.
    def self.request_locale
      I18n.available_locales.include?(I18n.locale) ? { locale: I18n.locale.to_s } : {}
    end
  end
end
