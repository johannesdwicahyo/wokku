module Dashboard
  module Apps
    class PerformanceController < BaseController
      before_action :set_app

      WINDOW = 7.days

      def show
        authorize @app, :show?
        @app.ensure_vitals_ingest_token!

        @latest = VitalsHourlyRollup.latest_by_metric(@app)
        @series = VitalsHourlyRollup
                    .for_app(@app)
                    .since(WINDOW.ago.beginning_of_hour)
                    .asc_t
                    .group_by(&:metric)
        @snippet = %(<script defer src="https://#{request.host}/v.js?t=#{@app.vitals_ingest_token}"></script>)
      end

      def rotate_token
        authorize @app, :update?
        @app.rotate_vitals_ingest_token!
        redirect_to dashboard_app_performance_path(@app), notice: t("dashboard.performance.token_rotated", default: "Token rotated.")
      end

      private

      def set_app
        @app = AppRecord.lookup!(params[:app_id])
      end
    end
  end
end
