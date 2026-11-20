module Api
  module V1
    module Agent
      # wokkud host-agent ingest. Authenticated by the same per-server
      # bearer token Vector uses (Server#ingest_token) — same trust
      # boundary: only a host we provisioned can write. Inherits
      # ActionController::API (NOT Api::V1::BaseController) to skip the
      # user ApiToken chain, mirroring Api::V1::Logs::IngestController.
      class BaseController < ActionController::API
        before_action :authenticate_server!

        private

        def authenticate_server!
          token = request.headers["Authorization"].to_s.sub(/^Bearer /, "")
          @server = Server.find_by_ingest_token(token) if token.present?
          head :unauthorized unless @server
        end
      end
    end
  end
end
