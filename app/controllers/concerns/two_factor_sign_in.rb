# The one door every web sign-in goes through (OAuth callbacks + the
# email/password form). A user with 2FA is not signed in here: we park
# their id in the session and send them to Users::TwoFactorChallenges,
# which signs them in after a TOTP or recovery code.
module TwoFactorSignIn
  extend ActiveSupport::Concern

  PENDING_TTL = 5.minutes
  PENDING_KEYS = %i[two_factor_user_id two_factor_started_at two_factor_remember].freeze

  private

  # Returns true when the user was signed in, false when a challenge started.
  def sign_in_with_two_factor(user, remember: false)
    unless user.two_factor_enabled?
      sign_in_and_redirect user, event: :authentication
      return true
    end

    # Devise's stored location (session["user_return_to"]) is left alone so
    # the challenge can land the user where they were going.
    clear_pending_two_factor
    session[:two_factor_user_id] = user.id
    session[:two_factor_started_at] = Time.current.to_i
    session[:two_factor_remember] = remember
    redirect_to users_two_factor_path
    false
  end

  def clear_pending_two_factor
    PENDING_KEYS.each { |k| session.delete(k) }
  end
end
