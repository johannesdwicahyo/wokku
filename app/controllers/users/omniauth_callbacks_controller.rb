class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # Apple returns with a cross-site form POST that carries no Rails
  # authenticity token; OmniAuth's state parameter is the CSRF check.
  skip_before_action :verify_authenticity_token, only: :apple

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
      _team, first_time_signup = @user.ensure_personal_team!
      if first_time_signup
        OnboardingMailer.welcome(@user).deliver_later rescue nil
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
      _team, first_time_signup = @user.ensure_personal_team!
      if first_time_signup
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

  def apple
    auth = request.env["omniauth.auth"]
    if auth.blank?
      redirect_to root_path, alert: "Could not sign in with Apple."
      return
    end
    raw = (auth.extra&.raw_info || {}).to_h
    claims = raw.merge("sub" => auth.uid, "email" => raw["email"] || auth.info&.email)
    @user = User.from_apple(claims, name: auth.info&.name)

    if @user.persisted?
      @user.remember_apple_refresh_token!(auth.dig("credentials", "refresh_token"), client_id: ::Apple::Config.services_id)
      finish_sign_in("Apple")
    else
      redirect_to new_user_session_path, alert: "Could not sign in with Apple."
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
      finish_sign_in(provider)
    else
      redirect_to new_user_session_path, alert: "Could not sign in with #{provider}."
    end
  end

  def finish_sign_in(provider)
    _team, first_time_signup = @user.ensure_personal_team!
    if first_time_signup
      # Welcome email — fire-and-forget, never block the auth callback
      # if mail delivery wobbles.
      OnboardingMailer.welcome(@user).deliver_later rescue nil
      # A deploy template chosen on the landing page survives the OAuth
      # round-trip via session; surface it on the dashboard.
      if (tmpl = session.delete(:pending_template)).present?
        flash[:deploy_template] = tmpl
      end
      flash[:posthog_event] = "signup_completed"
      flash[:posthog_props] = { provider: provider.downcase }
    end

    sign_in_and_redirect @user, event: :authentication
    set_flash_message(:notice, :success, kind: provider) if is_navigational_format?
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
