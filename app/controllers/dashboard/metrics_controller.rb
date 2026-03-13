module Dashboard
  class MetricsController < BaseController
    before_action :set_app

    def show
      authorize @app, :show?
      @metrics = @app.metrics.order(recorded_at: :desc).limit(100)
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end
  end
end
