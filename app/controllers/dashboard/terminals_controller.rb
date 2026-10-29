module Dashboard
  class TerminalsController < BaseController
    def show
      if params[:app_id]
        # App console — enters the app's web container
        @app = AppRecord.find(params[:app_id])
        @server = @app.server
        # A container shell exposes every secret: members and admins only.
        authorize @app, :update?
        @console_type = :app
      else
        # Server terminal — team admin only, full Dokku shell
        @server = policy_scope(Server).find(params[:server_id])
        authorize @server, :admin_terminal?
        @console_type = :server
      end
    rescue Pundit::NotAuthorizedError
      redirect_to dashboard_apps_path,
        alert: @console_type == :server || params[:app_id].blank? ? "Server terminal is only available to team admins." : "The app console needs the member or admin role."
    end
  end
end
