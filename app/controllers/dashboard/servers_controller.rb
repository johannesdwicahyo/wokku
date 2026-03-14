module Dashboard
  class ServersController < BaseController
    before_action :set_server, only: [:show, :destroy, :sync]

    def index
      @servers = policy_scope(Server).includes(:app_records)
      @server = Server.new
    end

    def show
      authorize @server
      @apps = @server.app_records
    end

    def new
      @server = Server.new
    end

    def create
      @server = Server.new(server_params.merge(team: current_team))
      authorize @server

      if @server.save
        redirect_to dashboard_server_path(@server), notice: "Server added successfully."
      else
        @servers = policy_scope(Server).includes(:app_records)
        render :index, status: :unprocessable_entity
      end
    end

    def sync
      authorize @server
      SyncServerJob.perform_later(@server.id)
      redirect_to dashboard_server_path(@server), notice: "Server sync started. Apps will appear shortly."
    end

    def destroy
      authorize @server
      @server.destroy
      redirect_to dashboard_servers_path, notice: "Server removed successfully."
    end

    private

    def set_server
      @server = Server.find(params[:id])
    end

    def server_params
      params.require(:server).permit(:name, :host, :port, :ssh_user, :ssh_private_key)
    end
  end
end
