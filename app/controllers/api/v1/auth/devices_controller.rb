module Api
  module V1
    module Auth
      class DevicesController < ActionController::API
        include ApiAuthenticatable

        skip_before_action :authenticate_api_token!, only: [ :code, :token ]

        def code
          auth = DeviceAuthorization.start!
          base = request.base_url
          render json: {
            device_code: auth.device_code,
            user_code: auth.user_code,
            verification_uri: "#{base}/dashboard/device",
            verification_uri_complete: "#{base}/dashboard/device?user_code=#{auth.user_code}",
            expires_in: DeviceAuthorization::EXPIRES_IN.to_i,
            interval: DeviceAuthorization::POLL_INTERVAL.to_i
          }, status: :ok
        end

        def token
          auth = DeviceAuthorization.find_by(device_code: params[:device_code].to_s)

          return render json: { error: "expired_token" }, status: :gone if auth.nil? || auth.expired?

          if auth.last_polled_at && auth.last_polled_at > DeviceAuthorization::POLL_INTERVAL.ago
            return render json: { error: "slow_down" }, status: :bad_request
          end
          auth.touch_polled!

          case auth.status
          when "pending"
            render json: { error: "authorization_pending" }, status: :accepted
          when "denied"
            render json: { error: "access_denied" }, status: :forbidden
          when "approved"
            plain_token = auth.consume_plain_token!
            if plain_token.nil?
              render json: { error: "token_already_retrieved" }, status: :gone
            else
              render json: {
                token: plain_token,
                user: { id: auth.user.id, email: auth.user.email, role: auth.user.role }
              }, status: :ok
            end
          end
        end
      end
    end
  end
end
