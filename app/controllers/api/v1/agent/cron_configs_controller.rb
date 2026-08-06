module Api
  module V1
    module Agent
      # Track B B3: wokkud fetches its declarative cron schedule here
      # whenever the heartbeat's cron_config_version differs from what it
      # last applied. Same ingest_token trust boundary as the rest of
      # Api::V1::Agent.
      class CronConfigsController < BaseController
        def show
          render json: Cron::ConfigBuilder.new(@server).as_json
        end
      end
    end
  end
end
