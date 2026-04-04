module Dashboard
  class LogDrainsController < BaseController
    before_action :set_app

    def create
      authorize @app, :update?
      @log_drain = @app.log_drains.build(log_drain_params)

      if @log_drain.save
        client = Dokku::Client.new(@app.server)
        Dokku::LogDrains.new(client).add(@app.name, @log_drain.url)
        redirect_to dashboard_app_logs_path(@app), notice: "Log drain added successfully."
      else
        redirect_to dashboard_app_logs_path(@app), alert: @log_drain.errors.full_messages.to_sentence
      end
    rescue StandardError => e
      redirect_to dashboard_app_logs_path(@app), alert: "Failed to add log drain: #{e.message}"
    end

    def destroy
      authorize @app, :update?
      log_drain = @app.log_drains.find(params[:id])

      client = Dokku::Client.new(@app.server)
      Dokku::LogDrains.new(client).remove(@app.name)

      log_drain.destroy
      redirect_to dashboard_app_logs_path(@app), notice: "Log drain removed successfully."
    rescue StandardError => e
      redirect_to dashboard_app_logs_path(@app), alert: "Failed to remove log drain: #{e.message}"
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end

    def log_drain_params
      params.require(:log_drain).permit(:url, :drain_type)
    end
  end
end
