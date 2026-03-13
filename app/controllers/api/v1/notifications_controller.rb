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
          render json: { errors: notification.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        notification = Notification.find(params[:id])
        authorize notification
        notification.destroy!
        render json: { message: "Notification removed" }
      end

      private

      def notification_params
        params.permit(:channel, :app_record_id, events: [], config: {})
      end
    end
  end
end
