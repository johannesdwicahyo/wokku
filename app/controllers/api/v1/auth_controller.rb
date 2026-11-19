module Api
  module V1
    class AuthController < ActionController::API
      include ApiAuthenticatable

      skip_before_action :authenticate_api_token!, only: [ :login, :apple, :mobile_token ]

      def login
        user = User.find_by(email: params[:email])
        if user&.valid_password?(params[:password])
          # Admin must have 2FA enabled; any 2FA user must provide otp_code
          # (authenticator or recovery code).
          if user.admin? && !user.two_factor_enabled?
            return render json: { error: "Admin must enable 2FA before using the API. Log in at wokku.cloud first." }, status: :forbidden
          end
          if user.two_factor_enabled? && !user.consume_second_factor!(params[:otp_code])
            track_failed_login!
            return render json: { error: "Invalid or missing OTP code. Provide otp_code parameter." }, status: :unauthorized
          end

          token, plain_token = ApiToken.create_with_token!(
            user: user,
            name: params[:name] || "cli-#{Time.current.to_i}"
          )
          render json: {
            token: plain_token,
            user: { id: user.id, email: user.email, role: user.role }
          }, status: :created
        else
          track_failed_login!
          render json: { error: "Invalid email or password" }, status: :unauthorized
        end
      end

      # Native Sign in with Apple (iOS). The app sends Apple's identity token,
      # the raw nonce it hashed into the request, and optionally the one-time
      # authorization code + name (Apple gives the name only on first sign-in).
      def apple
        return auth_error(:apple_unavailable) unless ::Apple::Config.native_configured?
        if params[:identity_token].blank? || params[:nonce].blank?
          return auth_error(:invalid_params, "identity_token and nonce are required", status: :unprocessable_entity)
        end

        claims = ::Apple::IdentityToken.verify!(params[:identity_token].to_s, nonce: params[:nonce].to_s)
        user = User.from_apple(claims, name: apple_name)
        unless user.persisted?
          track_failed_login!
          return auth_error(:registration_closed)
        end
        if user.admin?
          track_failed_login!
          return auth_error(:not_authorized, "Admin accounts sign in with password + 2FA.")
        end
        if user.two_factor_enabled?
          return auth_error(:two_factor_required)
        end

        user.ensure_personal_team!
        if params[:authorization_code].present?
          refresh = ::Apple::Client.exchange_code(params[:authorization_code].to_s, client_id: ::Apple::Config.bundle_id)
          user.remember_apple_refresh_token!(refresh, client_id: ::Apple::Config.bundle_id)
        end

        _token, plain_token = ApiToken.create_with_token!(user: user, name: params[:token_name].presence || "ios-#{Time.current.to_i}")
        render json: { token: plain_token, user: { id: user.id, email: user.email, role: user.role } }, status: :created
      rescue ::Apple::IdentityToken::Invalid
        track_failed_login!
        auth_error(:invalid_token, "Apple identity token is invalid")
      rescue ::Apple::IdentityToken::Unavailable
        auth_error(:apple_upstream_failed)
      end

      # iOS web sign-in handoff: the app redeems the one-time code from
      # wokku://auth with the PKCE verifier it kept.
      def mobile_token
        code = params[:code].to_s
        verifier = params[:code_verifier].to_s
        if code.blank? || !verifier.length.between?(43, 128)
          return auth_error(:invalid_params, "code and a 43-128 character code_verifier are required", status: :unprocessable_entity)
        end

        user = MobileAuthCode.redeem(code: code, code_verifier: verifier)
        unless user
          track_failed_login!
          return auth_error(:invalid_token, "Sign-in code is invalid or expired")
        end

        _token, plain_token = ApiToken.create_with_token!(user: user, name: params[:token_name].to_s.first(100).presence || "ios-#{Time.current.to_i}")
        render json: { token: plain_token, user: { id: user.id, email: user.email, role: user.role } }, status: :created
      end

      private

      # Increment the Fail2Ban counter on failed auth so repeat offenders
      # from the same IP get banned for an hour after 20 failures in 10 min.
      def track_failed_login!
        Rack::Attack::Fail2Ban.filter(
          "api_login:#{request.ip}",
          maxretry: 20,
          findtime: 10.minutes,
          bantime: 1.hour
        ) { true }
      end

      # AuthController is not a BaseController (no render_api_error).
      def auth_error(code, message = nil, status: nil)
        render json: ApiErrors.payload(code, message: message), status: status || ApiErrors.status(code)
      end

      def apple_name
        name = params[:name]
        return name.to_s.presence unless name.respond_to?(:key?)
        [ name[:given_name], name[:family_name] ].compact_blank.join(" ").presence
      end

      public

      def logout
        current_api_token.revoke!
        render json: { message: "Logged out" }
      end

      def whoami
        render json: {
          id: current_user.id,
          email: current_user.email,
          role: current_user.role
        }
      end
    end
  end
end
