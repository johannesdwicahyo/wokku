module Api
  module V1
    class ConfigController < BaseController
      before_action :set_app_record
      before_action :authorize_app

      def show
        client = Dokku::Client.new(@app_record.server)
        config = Dokku::Config.new(client)
        vars = config.list(@app_record.name)
        render json: { config: vars }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end

      def update
        raw = params[:vars]
        return render json: { error: "vars parameter required" }, status: :bad_request unless raw.respond_to?(:to_h)
        # vars is a dynamic key-value map (env var names are user-defined),
        # so we can't enumerate via permit. to_unsafe_h is the documented
        # API for free-form param hashes; values still flow through Dokku
        # which validates env-var name shape.
        vars = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.stringify_keys : raw.to_h.stringify_keys
        return render json: { error: "vars parameter required" }, status: :bad_request if vars.empty?

        client = Dokku::Client.new(@app_record.server)
        config = Dokku::Config.new(client)
        config.set(@app_record.name, vars)

        # Sync to local database
        vars.each do |key, value|
          env_var = @app_record.env_vars.find_or_initialize_by(key: key)
          env_var.update!(value: value)
        end

        track("config.updated", target: @app_record)
        render json: { message: "Config updated", vars: vars.keys }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end

      def destroy
        keys = Array(params[:keys])
        return render json: { error: "keys parameter required" }, status: :bad_request if keys.empty?

        client = Dokku::Client.new(@app_record.server)
        config = Dokku::Config.new(client)
        config.unset(@app_record.name, *keys)

        # Remove from local database
        @app_record.env_vars.where(key: keys).destroy_all

        render json: { message: "Config vars removed", keys: keys }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end

      private

      def set_app_record
        @app_record = AppRecord.lookup!(params[:app_id])
      end

      def authorize_app
        authorize @app_record, :show?
      end
    end
  end
end
