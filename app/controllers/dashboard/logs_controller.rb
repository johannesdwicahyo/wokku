module Dashboard
  class LogsController < BaseController
    before_action :set_app

    def show
      authorize @app, :show?
      @logs = fetch_recent_logs
      @log_drains = @app.log_drains
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end

    def fetch_recent_logs
      client = Dokku::Client.new(@app.server)
      lines = (params[:lines] || 200).to_i
      raw = Dokku::Logs.new(client).recent(@app.name, lines: lines)
      # Strip ANSI escape codes
      raw&.gsub(/\e\[[0-9;]*m/, "")
    rescue => e
      Rails.logger.warn "Failed to fetch logs for #{@app.name}: #{e.message}"
      nil
    end
  end
end
