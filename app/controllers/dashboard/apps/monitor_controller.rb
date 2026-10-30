module Dashboard
  module Apps
    # Per-app HTTP-request monitor page at /dashboard/apps/:app_id/monitor.
    # Reads RequestAggregate rows (5-min buckets) populated by
    # Apps::VisitTracker from the host heartbeat.
    class MonitorController < BaseController
      before_action :set_app

      WINDOW = 24.hours

      def show
        authorize @app, :show?

        @since = Time.current - WINDOW
        @buckets = RequestAggregate.for_app(@app).since(@since).asc_t.to_a
        @latest  = @buckets.last
        @recent_slow = RequestSample.for_app(@app).since(1.hour.ago)
                                     .where.not(response_time_ms: nil)
                                     .slow.limit(10)

        @totals = compute_totals(@buckets)
      end

      private

      def set_app
        @app = AppRecord.lookup!(params[:app_id])
      end

      def compute_totals(buckets)
        return default_totals if buckets.empty?

        req_count = buckets.sum(&:req_count)
        err_4xx   = buckets.sum(&:error_4xx)
        err_5xx   = buckets.sum(&:error_5xx)
        # Window-level p95 is approximated by the max of per-bucket p95s.
        # True percentile would require re-aggregating samples; the bucket
        # p95 is close enough for an at-a-glance number.
        p95 = buckets.map(&:p95_ms).compact.max
        rpm = (req_count.to_f / (WINDOW / 60)).round(1)

        {
          req_count: req_count,
          rpm: rpm,
          p95_ms: p95,
          error_rate: req_count.zero? ? 0.0 : (err_4xx + err_5xx).to_f / req_count,
          error_4xx: err_4xx,
          error_5xx: err_5xx
        }
      end

      def default_totals
        { req_count: 0, rpm: 0.0, p95_ms: nil, error_rate: 0.0, error_4xx: 0, error_5xx: 0 }
      end
    end
  end
end
