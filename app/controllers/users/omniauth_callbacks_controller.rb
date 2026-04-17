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
      if @user.teams.empty?
        team = Team.create!(name: "#{@user.name || @user.email.split('@').first}'s Team", owner: @user)
        TeamMembership.create!(user: @user, team: team, role: :admin)
      end

      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: provider) if is_navigational_format?
    else
      redirect_to new_user_session_path, alert: "Could not sign in with #{provider}."
    end
  end
end
