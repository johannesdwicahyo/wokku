module Dashboard
  class NotificationsController < BaseController
    def index
      @notifications = current_team.notifications.includes(:app_record).order(created_at: :desc)
      @notification = Notification.new
      @apps = policy_scope(AppRecord)
    end

    def create
      @notification = current_team.notifications.build(notification_params)
      authorize @notification

      if @notification.save
        redirect_to dashboard_notifications_path, notice: "Notification rule created."
      else
        @notifications = current_team.notifications.includes(:app_record)
        @apps = policy_scope(AppRecord)
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      @notification = current_team.notifications.find(params[:id])
      authorize @notification
      @notification.destroy
      redirect_to dashboard_notifications_path, notice: "Notification rule removed."
    end

    # Fire a sample message right now so the user can verify config
    # without waiting for a real deploy event. Sentinel deploy_id=0
    # tells NotifyJob to render with no Deploy context.
    def test
      @notification = current_team.notifications.find(params[:id])
      authorize @notification, :create?
      event = @notification.events.first || "deploy_succeeded"
      NotifyJob.perform_later(@notification.id, event, 0)
      redirect_to dashboard_notifications_path, notice: "Test #{@notification.channel} notification queued — should arrive in a few seconds."
    end

    private

    def notification_params
      params.require(:notification).permit(:channel, :app_record_id, events: [], config: {})
    end
  end
end
