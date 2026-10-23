module Api
  module V1
    class DevicesController < BaseController
      def create
        first_device = !current_user.device_tokens.exists?
        token = current_user.device_tokens.find_or_initialize_by(token: params[:token])
        token.platform = params[:platform]
        token.provider = params[:provider].presence || "expo"

        if token.save
          Notification.ensure_default_push_for!(current_user) if first_device
          render json: { registered: true }
        else
          render_api_error(:validation_failed, message: token.errors.full_messages.to_sentence, details: token.errors.full_messages)
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
