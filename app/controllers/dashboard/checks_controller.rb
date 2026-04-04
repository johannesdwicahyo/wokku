module Dashboard
  class ChecksController < BaseController
    before_action :set_app

    def show
      authorize @app, :show?

      client = Dokku::Client.new(@app.server)
      @checks = Dokku::Checks.new(client).report(@app.name)
    rescue => e
      @checks = {}
      flash.now[:alert] = "Could not fetch checks report: #{e.message}"
    end

    def update
      authorize @app, :update?

      client = Dokku::Client.new(@app.server)
      checks = Dokku::Checks.new(client)

      if params[:checks_enabled] == "1"
        checks.enable(@app.name)
      else
        checks.disable(@app.name)
      end

      %w[CHECKS_WAIT CHECKS_TIMEOUT CHECKS_ATTEMPTS].each do |key|
        param_key = key.downcase
        value = params[param_key].to_s.strip
        checks.set(@app.name, key, value) if value.present?
      end

      if params[:check_path].present?
        checks.set(@app.name, "CHECKS_PATH", params[:check_path].strip)
      end

      redirect_to dashboard_app_checks_path(@app), notice: "Health check settings saved."
    rescue => e
      redirect_to dashboard_app_checks_path(@app), alert: "Failed to update checks: #{e.message}"
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end
  end
end
