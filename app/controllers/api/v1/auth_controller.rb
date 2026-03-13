module Api
  module V1
    class AuthController < ActionController::API
      include ApiAuthenticatable

      skip_before_action :authenticate_api_token!, only: [:login]

      def login
        user = User.find_by(email: params[:email])
        if user&.valid_password?(params[:password])
          token, plain_token = ApiToken.create_with_token!(
            user: user,
            name: params[:name] || "cli-#{Time.current.to_i}"
          )
          render json: {
            token: plain_token,
            user: { id: user.id, email: user.email, role: user.role }
          }, status: :created
        else
          render json: { error: "Invalid email or password" }, status: :unauthorized
        end
      end

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
