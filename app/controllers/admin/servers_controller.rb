module Admin
  class ServersController < BaseController
    before_action :set_server, only: [ :show, :destroy, :sync ]

    def index
      authorize Server, :show?
      @servers = policy_scope(Server).includes(:app_records)
      @server = Server.new
      @can_manage = Pundit.policy(current_user, Server).manage?
    end

    def show
      authorize @server, :show?
      @apps = @server.app_records.where(team: current_user.teams)
      @can_manage = Pundit.policy(current_user, @server).manage?
    end

    def new
      @server = Server.new
    end

    def create
      # Platform servers — no team ownership; track the adding admin via
      # the activity log instead.
      @server = Server.new(server_params)
      authorize @server

      if @server.save
        # Create the server's DNS record in the canonical zone only.
        Wokku.config.dns_provider.create_app_record(@server.name, @server.host) rescue nil

        track("server.created", target: @server)
        redirect_to admin_server_path(@server), notice: "Server added successfully."
      else
        @servers = policy_scope(Server).includes(:app_records)
        render :index, status: :unprocessable_entity
      end
    end

    def sync
      authorize @server, :manage?
      SyncServerJob.perform_later(@server.id)
      redirect_to admin_server_path(@server), notice: "Server sync started. Apps will appear shortly."
    end

    def destroy
      authorize @server

      # Clean up DNS record on every Wokku zone.
      Wokku.config.dns_provider.delete_app_record(@server.name) rescue nil

      @server.destroy
      track("server.destroyed", target: @server)
      redirect_to admin_servers_path, notice: "Server removed successfully."
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
