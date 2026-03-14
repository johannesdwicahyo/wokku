module Dashboard
  class AppsController < BaseController
    before_action :set_app, only: [:show, :destroy]

    def index
      @apps = policy_scope(AppRecord).includes(:server, :team)
      @app = AppRecord.new
      @servers = policy_scope(Server)
    end

    def show
      authorize @app
    end

    def new
      @app = AppRecord.new
      @servers = policy_scope(Server)
    end

    def create
      team = current_team
      server = policy_scope(Server).find(params[:app_record][:server_id])
      @app = AppRecord.new(app_params.merge(team: team, creator: current_user, server: server))
      authorize @app

      if @app.save
        redirect_to dashboard_app_path(@app), notice: "App created successfully."
      else
        @servers = policy_scope(Server)
        @apps = policy_scope(AppRecord).includes(:server, :team)
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @app
      @app.destroy
      redirect_to dashboard_apps_path, notice: "App deleted successfully."
    end

    private

    def set_app
      @app = AppRecord.find(params[:id])
    end

    def app_params
      params.require(:app_record).permit(:name, :deploy_branch)
    end
  end
end
