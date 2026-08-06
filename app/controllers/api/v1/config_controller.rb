module Api
  module V1
    class ConfigController < BaseController
      before_action :set_app_record
      before_action :authorize_app

      def show
        render json: { config: @app_record.runtime_env }
      end

      def update
        raw = params[:vars]
        return render_api_error(:invalid_params, message: "vars parameter required") unless raw.respond_to?(:to_h)
        # vars is a dynamic key-value map (env var names are user-defined),
        # so we can't enumerate via permit. to_unsafe_h is the documented
        # API for free-form param hashes; values still flow through Dokku
        # which validates env-var name shape.
        vars = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.stringify_keys : raw.to_h.stringify_keys
        return render_api_error(:invalid_params, message: "vars parameter required") if vars.empty?

        ::Apps::EnvWriter.set(@app_record, vars)

        track("config.updated", target: @app_record)
        render json: {
          message: "Config updated. Restart the app for changes to take effect.",
          vars: vars.keys,
          restart_required: true
        }
      end

      def destroy
        keys = Array(params[:keys])
        return render_api_error(:invalid_params, message: "keys parameter required") if keys.empty?

        ::Apps::EnvWriter.unset(@app_record, *keys)

        render json: {
          message: "Config vars removed. Restart the app for changes to take effect.",
          keys: keys,
          restart_required: true
        }
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
