module Api
  module V1
    module Agent
      # Track B B3: wokkud fetches an app's env right before firing a cron
      # entry, so values are always current instead of baked into the
      # declarative config. Scoped to apps hosted on the requesting server —
      # same trust boundary as the rest of Api::V1::Agent.
      class AppEnvsController < BaseController
        def show
          app = @server.app_records.find_by(name: params[:name])
          return render json: ApiErrors.payload(:app_not_on_server), status: ApiErrors.status(:app_not_on_server) unless app

          render json: { env: app.runtime_env }
        end
      end
    end
  end
end
