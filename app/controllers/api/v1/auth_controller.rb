module Api
  module V1
    class AuthController < ActionController::API
      include ApiAuthenticatable

      skip_before_action :authenticate_api_token!, only: [ :login ]

      def login
        user = User.find_by(email: params[:email])
        if user&.valid_password?(params[:password])
          # Admin must have 2FA enabled and provide OTP code
          if user.admin?
            unless user.two_factor_enabled?
              return render json: { error: "Admin must enable 2FA before using the API. Log in at wokku.cloud first." }, status: :forbidden
            end
            unless user.validate_and_consume_otp!(params[:otp_code].to_s)
              track_failed_login!
              return render json: { error: "Invalid or missing OTP code. Provide otp_code parameter." }, status: :unauthorized
            end
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
