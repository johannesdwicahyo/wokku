module Api
  module V1
    class ServersController < BaseController
      def index
        authorize Server, :show?
        servers = policy_scope(Server)
        render json: servers.select(:id, :name, :host, :port, :status, :created_at)
      end

      def show
        server = Server.lookup!(params[:id])
        authorize server, :show?
        render json: server.as_json(except: [ :ssh_private_key ])
      end

      def create
        # Platform servers — no team ownership. Only system admins can add.
        server = Server.new(server_params)
        authorize server

        if server.save
          render json: server.as_json(except: [ :ssh_private_key ]), status: :created
        else
          render json: { errors: server.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        server = Server.lookup!(params[:id])
        authorize server
        server.destroy!
        render json: { message: "Server removed" }
      end

      def status
        server = Server.lookup!(params[:id])
        authorize server, :manage?
        client = Dokku::Client.new(server)
        connected = client.connected?
        server.update_column(:status, Server.statuses[connected ? :connected : :unreachable])
        render json: { status: server.reload.status, connected: connected }
      end

      private

      def server_params
        params.permit(:name, :host, :port, :ssh_user, :ssh_private_key)
      end
    end
  end
end
