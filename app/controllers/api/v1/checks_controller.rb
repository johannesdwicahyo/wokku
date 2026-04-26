module Api
  module V1
    class ChecksController < BaseController
      before_action :set_app_record

      def show
        authorize @app_record, :show?

        client = Dokku::Client.new(@app_record.server)
        report = Dokku::Checks.new(client).report(@app_record.name)
        render json: { checks: report }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end

      def update
        authorize @app_record, :update?

        client = Dokku::Client.new(@app_record.server)
        checks = Dokku::Checks.new(client)

        if params[:enabled].present?
          if params[:enabled].to_s == "true"
            checks.enable(@app_record.name)
          else
            checks.disable(@app_record.name)
          end
        end

        %w[CHECKS_WAIT CHECKS_TIMEOUT CHECKS_ATTEMPTS].each do |key|
          param_key = key.downcase.delete_prefix("checks_")
          value = params[param_key.to_sym].to_s.strip
          checks.set(@app_record.name, key, value) if value.present?
        end

        if params[:path].present?
          checks.set(@app_record.name, "CHECKS_PATH", params[:path].strip)
        end

        render json: { message: "Health check settings updated" }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end

      private

      def set_app_record
        @app_record = AppRecord.lookup!(params[:app_id])
      end
    end
  end
end
