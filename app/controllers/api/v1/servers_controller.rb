module Api
  module V1
    class ServersController < BaseController
      def index
        servers = policy_scope(Server)
        render json: servers.select(:id, :name, :host, :port, :status, :created_at)
      end

      def show
        server = Server.find(params[:id])
        authorize server
        render json: server.as_json(except: [:ssh_private_key])
      end

      def create
        team = current_user.teams.find(params[:team_id])
        server = team.servers.build(server_params)
        authorize server

        if server.save
          render json: server.as_json(except: [:ssh_private_key]), status: :created
        else
          render json: { errors: server.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        server = Server.find(params[:id])
        authorize server
        server.destroy!
        render json: { message: "Server removed" }
      end

      def status
        server = Server.find(params[:id])
        authorize server
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
