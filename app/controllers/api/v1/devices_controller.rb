module Api
  module V1
    class DevicesController < BaseController
      def create
        token = current_user.device_tokens.find_or_initialize_by(token: params[:token])
        token.platform = params[:platform]

        if token.save
          render json: { registered: true }
        else
          render json: { errors: token.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        token = current_user.device_tokens.find_by(token: params[:id])
        token&.destroy
        render json: { unregistered: true }
      end
    end
  end
end
