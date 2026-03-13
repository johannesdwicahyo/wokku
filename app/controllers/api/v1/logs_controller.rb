module Api
  module V1
    class LogsController < BaseController
      def index
        app_record = AppRecord.find(params[:app_id])
        authorize app_record, :show?

        lines = (params[:lines] || 100).to_i
        client = Dokku::Client.new(app_record.server)
        output = Dokku::Logs.new(client).recent(app_record.name, lines: lines)

        render json: { logs: output }
      rescue Dokku::Client::CommandError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue Dokku::Client::ConnectionError => e
        render json: { error: "Cannot connect to server: #{e.message}" }, status: :service_unavailable
      end
    end
  end
end
