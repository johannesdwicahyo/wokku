module Api
  module V1
    class LogDrainsController < BaseController
      before_action :set_app_record

      def index
        authorize @app_record, :show?
        render json: @app_record.log_drains
      end

      def create
        authorize @app_record, :update?
        log_drain = @app_record.log_drains.build(log_drain_params)

        if log_drain.save
          client = Dokku::Client.new(@app_record.server)
          Dokku::LogDrains.new(client).add(@app_record.name, log_drain.url)
          track("log_drain.added", target: log_drain)
          render json: log_drain, status: :created
        else
          render json: { errors: log_drain.errors.full_messages }, status: :unprocessable_entity
        end
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end

      def destroy
        log_drain = @app_record.log_drains.find(params[:id])
        authorize @app_record, :update?

        client = Dokku::Client.new(@app_record.server)
        Dokku::LogDrains.new(client).remove(@app_record.name)
        log_drain.destroy!
        track("log_drain.removed", target: log_drain)

        render json: { message: "Log drain removed" }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end

      private

      def set_app_record
        @app_record = AppRecord.lookup!(params[:app_id])
      end

      def log_drain_params
        params.permit(:url, :drain_type)
      end
    end
  end
end
