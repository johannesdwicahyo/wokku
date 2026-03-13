module Dashboard
  class ServersController < BaseController
    before_action :set_server, only: [:show, :destroy]

    def index
      @servers = policy_scope(Server).includes(:app_records)
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
        render :new, status: :unprocessable_entity
      end
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
      params.require(:server).permit(:name, :host, :port, :ssh_user)
    end
  end
end
