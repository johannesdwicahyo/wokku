module Api
  module V1
    class NotificationsController < BaseController
      def index
        notifications = policy_scope(Notification)
        render json: notifications
      end

      def create
        team = current_user.teams.find(params[:team_id])
        notification = team.notifications.build(notification_params)
        authorize notification

        if notification.save
          render json: notification, status: :created
        else
          render_api_error(:validation_failed, message: notification.errors.full_messages.to_sentence, details: notification.errors.full_messages)
        end
      end

      def destroy
        notification = policy_scope(Notification).find(params[:id])
        authorize notification
        notification.destroy!
        render json: { message: "Notification removed" }
      end

      # Send a sample message now so the channel config can be checked
      # without waiting for a real event (deploy_id 0 = no deploy context).
      def test
        notification = policy_scope(Notification).find(params[:id])
        authorize notification, :create?
        event = notification.events.first || "deploy_succeeded"
        NotifyJob.perform_later(notification.id, event, 0)
        render json: { message: "Test #{notification.channel} notification queued" }, status: :accepted
      end

      private

      def notification_params
        params.permit(:channel, :app_record_id, events: [], config: {})
      end
    end
  end
end
