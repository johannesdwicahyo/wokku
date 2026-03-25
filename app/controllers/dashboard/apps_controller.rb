module Dashboard
  class AppsController < BaseController
    before_action :set_app, only: [:show, :destroy, :restart, :stop, :start]

    def index
      @apps = policy_scope(AppRecord).includes(:server, :team, :domains)
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
        track("app.created", target: @app)
        redirect_to dashboard_app_path(@app), notice: "App created successfully."
      else
        @servers = policy_scope(Server)
        @apps = policy_scope(AppRecord).includes(:server, :team)
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @app
      begin
        client = Dokku::Client.new(@app.server)
        Dokku::Apps.new(client).destroy(@app.name)
      rescue Dokku::Client::CommandError, Dokku::Client::ConnectionError => e
        Rails.logger.warn("Failed to destroy #{@app.name} on Dokku: #{e.message}")
      end
      @app.destroy
      track("app.destroyed", target: @app)
      redirect_to dashboard_apps_path, notice: "App deleted successfully."
    end

    def restart
      authorize @app
      dokku_processes.restart(@app.name)
      @app.update(status: :running)
      track("app.restarted", target: @app)
      redirect_to dashboard_app_path(@app), notice: "#{@app.name} restarted."
    rescue => e
      redirect_to dashboard_app_path(@app), alert: "Restart failed: #{e.message}"
    end

    def stop
      authorize @app
      dokku_processes.stop(@app.name)
      @app.update(status: :stopped)
      track("app.stopped", target: @app)
      redirect_to dashboard_app_path(@app), notice: "#{@app.name} stopped."
    rescue => e
      redirect_to dashboard_app_path(@app), alert: "Stop failed: #{e.message}"
    end

    def start
      authorize @app
      dokku_processes.start(@app.name)
      @app.update(status: :running)
      track("app.started", target: @app)
      redirect_to dashboard_app_path(@app), notice: "#{@app.name} started."
    rescue => e
      redirect_to dashboard_app_path(@app), alert: "Start failed: #{e.message}"
    end

    private

    def set_app
      @app = AppRecord.find(params[:id])
    end

    def app_params
      params.require(:app_record).permit(:name, :deploy_branch)
    end

    def dokku_processes
      client = Dokku::Client.new(@app.server)
      Dokku::Processes.new(client)
    end
  end
end
