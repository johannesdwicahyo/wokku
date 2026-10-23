module Api
  module V1
    # The caller's own push mutes. Other users' rows are invisible (404).
    class AlertMutesController < BaseController
      def index
        render json: current_user.alert_mutes.active.includes(:app_record).order(:created_at).map(&:as_api_json)
      end

      def create
        app = policy_scope(AppRecord).lookup!(params[:app_id]) if params[:app_id].present?
        event = params[:event].presence
        return invalid("event must be one of: #{AlertMute::EVENTS.join(', ')}") if event && !AlertMute::EVENTS.include?(event)
        return invalid("give app_id and/or event — to silence everything, unregister the device instead") unless app || event

        expires_at = nil
        if params[:until].present?
          expires_at = parse_time(params[:until])
          return invalid("until must be a future ISO 8601 time") unless expires_at&.future?
        end

        mute = current_user.alert_mutes.find_or_initialize_by(app_record: app, event: event)
        mute.update!(expires_at: expires_at)
        render json: mute.as_api_json, status: :created
      end

      def destroy
        current_user.alert_mutes.find(params[:id]).destroy!
        render json: { message: "Mute removed" }
      end

      private

      def parse_time(value)
        Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end

      def invalid(message)
        render_api_error(:invalid_params, message: message, status: :unprocessable_entity)
      end
    end
  end
end
