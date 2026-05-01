module Dashboard
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
        # Create DNS record: server-name.wokku.cloud → server IP
        Cloudflare::Dns.new.create_app_record(@server.name, @server.host) rescue nil

        track("server.created", target: @server)
        redirect_to dashboard_server_path(@server), notice: "Server added successfully."
      else
        @servers = policy_scope(Server).includes(:app_records)
        render :index, status: :unprocessable_entity
      end
    end

    def provision
      authorize Server, :create?

      credential = current_team.cloud_credentials.find(params[:cloud_credential_id])
      provider = CloudProviders.const_get(credential.provider.capitalize).new(credential)

      # Generate SSH key pair for this server
      key = OpenSSL::PKey::RSA.new(4096)
      ssh_private_key = key.to_pem
      ssh_public_key = "ssh-rsa #{[ key.public_key.to_blob ].pack('m0')}"

      # Create VPS via provider API
      result = provider.create_server(
        name: params[:name],
        region: params[:region],
        size: params[:size]
      )

      # Platform server — no team assignment
      server = Server.create!(
        name: params[:name],
        host: result[:ip],
        port: 22,
        ssh_user: "root",
        ssh_private_key: ssh_private_key,
        cloud_provider: credential.provider,
        cloud_server_id: result[:id],
        monthly_cost_cents: params[:monthly_cost_cents].to_i,
        status: :syncing
      )

      # Create DNS record: server-name.wokku.cloud → server IP
      Cloudflare::Dns.new.create_app_record(server.name, result[:ip]) rescue nil

      # Queue Dokku installation
      ProvisionServerJob.perform_later(
        server_id: server.id,
        cloud_credential_id: credential.id,
        cloud_server_id: result[:id]
      )

      redirect_to dashboard_server_path(server), notice: "Server provisioning started. Dokku will be installed automatically (~5 minutes)."
    rescue => e
      redirect_to new_dashboard_server_path, alert: "Provisioning failed: #{e.message}"
    end

    def sync
      authorize @server, :manage?
      SyncServerJob.perform_later(@server.id)
      redirect_to dashboard_server_path(@server), notice: "Server sync started. Apps will appear shortly."
    end

    def destroy
      authorize @server

      # Clean up DNS record
      Cloudflare::Dns.new.delete_app_record(@server.name) rescue nil

      @server.destroy
      track("server.destroyed", target: @server)
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
