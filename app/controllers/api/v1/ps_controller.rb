module Api
  module V1
    class PsController < BaseController
      before_action :set_app_record

      def show
        authorize @app_record, :show?

        client = Dokku::Client.new(@app_record.server)
        report = Dokku::Processes.new(client).list(@app_record.name)
        render json: { processes: report }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end

      def update
        authorize @app_record, :update?

        scaling = params.permit(:scaling).to_h.fetch("scaling", params[:scaling])
        return render json: { error: "scaling parameter required" }, status: :bad_request unless scaling.is_a?(Hash)

        client = Dokku::Client.new(@app_record.server)
        Dokku::Processes.new(client).scale(@app_record.name, scaling)

        # Sync to local database
        scaling.each do |process_type, count|
          ps = @app_record.process_scales.find_or_initialize_by(process_type: process_type)
          ps.update!(count: count)
        end

        render json: { message: "Scaling updated", scaling: scaling }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end

      private

      def set_app_record
        @app_record = AppRecord.find(params[:app_id])
      end
    end
  end
end
