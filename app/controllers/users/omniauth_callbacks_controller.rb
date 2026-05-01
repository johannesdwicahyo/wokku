class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2
    handle_auth("Google")
  end

  def github
    handle_auth("GitHub")
  end

  def failure
    redirect_to root_path, alert: "Authentication failed: #{failure_message}"
  end

  private

  def handle_auth(provider)
    auth = request.env["omniauth.auth"]
    if auth.blank?
      redirect_to root_path, alert: "Could not sign in with #{provider}."
      return
    end
    @user = User.from_omniauth(auth)

    if @user.persisted?
      first_time_signup = @user.teams.empty?
      if first_time_signup
        team = Team.create!(name: "#{@user.name || @user.email.split('@').first}'s Team", owner: @user)
        TeamMembership.create!(user: @user, team: team, role: :admin)
        # Welcome email — fire-and-forget, never block the auth callback
        # if mail delivery wobbles.
        OnboardingMailer.welcome(@user).deliver_later rescue nil
        # Promo code from the landing-page ?code= param survives across
        # the OAuth round-trip via session. Apply it here (after the
        # team exists) so the user lands on the dashboard with a
        # pending redemption already attached.
        if (pending_code = session.delete(:pending_promo_code)).present?
          PromoCodes::Redeem.call(user: @user, code: pending_code)
        end
      end

      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: provider) if is_navigational_format?
    else
      redirect_to new_user_session_path, alert: "Could not sign in with #{provider}."
    end
  end
end
