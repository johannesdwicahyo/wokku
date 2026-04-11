module Dashboard
  class TerminalsController < BaseController
    def show
      if params[:app_id]
        # App console — enters the app's web container
        @app = AppRecord.find(params[:app_id])
        @server = @app.server
        authorize @server, :show?
        @console_type = :app
      else
        # Server terminal — team admin only, full Dokku shell
        @server = policy_scope(Server).find(params[:server_id])
        authorize @server, :admin_terminal?
        @console_type = :server
      end
    rescue Pundit::NotAuthorizedError
      redirect_to dashboard_apps_path,
        alert: "Server terminal is only available to team admins."
    end
  end
end
