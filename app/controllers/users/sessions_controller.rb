class Users::SessionsController < Devise::SessionsController
  include TwoFactorSignIn

  # A 2FA user with the right password goes to the challenge. Prepended so
  # it runs before Devise's allow_params_authentication!: once that is set,
  # any current_user call (e.g. a later before_action) runs the warden
  # strategies, and two_factor_authenticatable would sign the user in on a
  # posted otp_attempt. Everything else (wrong password, locked, unknown
  # email, non-2FA) falls through to Devise's create, failures counted once.
  prepend_before_action :challenge_two_factor_user, only: :create

  private

  def challenge_two_factor_user
    # CSRF first: without it, a forged POST would get a right/wrong
    # password answer (challenge vs. CSRF bounce) that lockable never counts.
    return unless verified_request?

    # The params warden's strategies read (Rack form/query params), not
    # Rails params: those differ when the query string and body disagree,
    # which would let Devise sign in a user this check never looked at.
    creds = Rack::Request.new(request.env).params["user"]
    return unless creds.is_a?(Hash)

    user = User.find_for_database_authentication(email: creds["email"].to_s)
    return unless user&.two_factor_enabled? && user.active_for_authentication? && user.valid_password?(creds["password"].to_s)

    sign_in_with_two_factor(user, remember: Devise::TRUE_VALUES.include?(creds["remember_me"]))
  end
end
