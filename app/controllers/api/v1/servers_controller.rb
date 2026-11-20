module Api
  module V1
    class ServersController < BaseController
      SUMMARY_FIELDS = %i[id name host port status created_at heartbeat_status heartbeat_at].freeze
      SECRET_FIELDS = %i[ssh_private_key ingest_token ingest_token_digest].freeze

      def index
        authorize Server, :show?
        servers = policy_scope(Server)
        render json: servers.select(*SUMMARY_FIELDS)
      end

      def show
        server = Server.lookup!(params[:id])
        authorize server, :show?
        # Any signed-in user may show a server (deploy target / terminal), but
        # operator details (cost, provider, ssh_user, vitals) are admin-only.
        if policy(server).manage?
          render json: server.as_json(except: SECRET_FIELDS)
        else
          render json: server.as_json(only: SUMMARY_FIELDS)
        end
      end

      def create
        # Platform servers — no team ownership. Only system admins can add.
        server = Server.new(server_params)
        authorize server

        if server.save
          render json: server.as_json(except: SECRET_FIELDS), status: :created
        else
          render_api_error(:validation_failed, message: server.errors.full_messages.to_sentence, details: server.errors.full_messages)
        end
      end

      def destroy
        server = Server.lookup!(params[:id])
        authorize server
        server.destroy!
        render json: { message: "Server removed" }
      end

      # W7 Phase 2: raw dokku passthrough retired — the fleet is dokku-free.
      # Route stays so old CLIs get a typed 410 instead of a routing 404.
      def dokku
        server = Server.lookup!(params[:id])
        authorize server, :dokku?
        render_api_error(:passthrough_retired)
      end

      def status
        server = Server.lookup!(params[:id])
        authorize server, :manage?
        # wokkud heartbeat freshness is the reachability truth (same source
        # apps#show/doctor surface) — no SSH probe.
        connected = !server.heartbeat_stale?
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
