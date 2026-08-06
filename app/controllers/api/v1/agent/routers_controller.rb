module Api
  module V1
    module Agent
      # Phase B1: wokkud fetches its declarative routing config here, and
      # Caddy's on-demand TLS `ask` gate calls tls_allowed before issuing a
      # cert for a custom domain. Same ingest_token trust boundary as the
      # rest of Api::V1::Agent, but tls_allowed also accepts ?token=
      # because Caddy's ask request can't set headers.
      class RoutersController < BaseController
        # ponytail: NOT named `config` — that's an AbstractController::Base
        # instance method (delegated to by `logger`), and shadowing it here
        # sends every internal `logger` lookup back through this action,
        # causing infinite render/log recursion (reproduced + confirmed).
        # `show` keeps the route/URL (`GET router/config`) unchanged.
        def show
          builder = Routers::ConfigBuilder.new(@server)
          render json: builder.as_json.merge("version" => builder.version)
        end

        def tls_allowed
          hostname = params[:domain].to_s.downcase
          # Self-host: the dashboard's own apex is TLS-eligible when the
          # control plane rides this Caddy (see Routers::ConfigBuilder).
          if ENV["WOKKU_CONTROL_PLANE_UPSTREAM"].present? &&
             hostname == Wokku.config.canonical_domain.downcase
            return head :ok
          end
          allowed = Domain.joins(:app_record)
                          .where(app_records: { server_id: @server.id }, dns_verified: true)
                          .exists?(hostname: hostname)
          if allowed
            head :ok
          else
            render json: ApiErrors.payload(:domain_not_verified),
                   status: ApiErrors.status(:domain_not_verified)
          end
        end

        private

        # Caddy's on-demand `ask` request appends only ?domain= and cannot
        # set an Authorization header — accept the ingest token as a query
        # param too, but ONLY for tls_allowed. `show` serves the wildcard
        # cert's key_pem and must stay header-only — a query param leaks
        # into access logs / referrers, an acceptable exposure for the
        # narrow tls_allowed yes/no gate but not for the private key.
        def authenticate_server!
          token = request.headers["Authorization"].to_s.sub(/^Bearer /, "").presence
          token ||= params[:token].to_s.presence if action_name == "tls_allowed"
          @server = Server.find_by(ingest_token: token) if token
          head :unauthorized unless @server
        end
      end
    end
  end
end
