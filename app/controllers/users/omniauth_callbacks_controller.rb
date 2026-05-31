class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2
    handle_auth("Google")
  end

  def github
    handle_auth("GitHub")
  end

  def gitlab
    auth = request.env["omniauth.auth"]
    if auth.blank?
      redirect_to root_path, alert: "Could not sign in with GitLab."
      return
    end
    @user = User.from_omniauth(auth)

    if @user.persisted?
      first_time_signup = @user.teams.empty?
      if first_time_signup
        team = Team.create!(name: "#{@user.name || @user.email.split("@").first}'s Team", owner: @user)
        TeamMembership.create!(user: @user, team: team, role: :admin)
        OnboardingMailer.welcome(@user).deliver_later rescue nil
        if (pending_code = session.delete(:pending_promo_code)).present?
          PromoCodes::Redeem.call(user: @user, code: pending_code)
        end
        if (tmpl = session.delete(:pending_template)).present?
          flash[:deploy_template] = tmpl
        end
        flash[:posthog_event] = "signup_completed"
        flash[:posthog_props] = { provider: "gitlab" }
      end

      persist_provider_tokens(:gitlab)
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: "GitLab") if is_navigational_format?
    else
      redirect_to new_user_session_path, alert: "Could not sign in with GitLab."
    end
  end

  def bitbucket
    auth = request.env["omniauth.auth"]
    if auth.blank?
      redirect_to root_path, alert: "Could not sign in with Bitbucket."
      return
    end
    @user = User.from_omniauth(auth)

    if @user.persisted?
      first_time_signup = @user.teams.empty?
      if first_time_signup
        team = Team.create!(name: "#{@user.name || @user.email.split("@").first}'s Team", owner: @user)
        TeamMembership.create!(user: @user, team: team, role: :admin)
        if (tmpl = session.delete(:pending_template)).present?
          flash[:deploy_template] = tmpl
        end
        flash[:posthog_event] = "signup_completed"
        flash[:posthog_props] = { provider: "bitbucket" }
      end

      persist_provider_tokens(:bitbucket)
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: "Bitbucket") if is_navigational_format?
    else
      redirect_to root_path, alert: "Could not sign in with Bitbucket: #{@user.errors.full_messages.join(", ")}"
    end
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
        if (tmpl = session.delete(:pending_template)).present?
          flash[:deploy_template] = tmpl
        end
        flash[:posthog_event] = "signup_completed"
        flash[:posthog_props] = { provider: provider.downcase }
      end

      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: provider) if is_navigational_format?
    else
      redirect_to new_user_session_path, alert: "Could not sign in with #{provider}."
    end
  end

  def persist_provider_tokens(provider)
    return unless @user&.persisted?
    creds = request.env.dig("omniauth.auth", "credentials") || {}
    expires_at = creds["expires_at"] ? Time.at(creds["expires_at"]) : nil

    @user.update!(
      "#{provider}_access_token" => creds["token"],
      "#{provider}_refresh_token" => creds["refresh_token"],
      "#{provider}_token_expires_at" => expires_at
    )
  end
end
