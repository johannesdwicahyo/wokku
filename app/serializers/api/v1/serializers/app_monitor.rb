module Api
  module V1
    module Serializers
      class AppMonitor
        WINDOW = 24.hours
        SLOW_LIMIT = 10

        def initialize(app)
          @app = app
        end

        def call
          buckets = RequestAggregate
                      .where(app_record_id: @app.id)
                      .where("bucket_start >= ?", WINDOW.ago)
                      .order(:bucket_start)
                      .to_a

          {
            app_id: @app.id,
            window_seconds: WINDOW.to_i,
            totals: totals(buckets),
            buckets: buckets.map { |b| serialize_bucket(b) },
            recent_slow: recent_slow.map { |s| serialize_sample(s) }
          }
        end

        private

        def totals(buckets)
          if buckets.empty?
            return { req_count: 0, rpm: 0.0, p50_ms: nil, p95_ms: nil,
                     error_4xx: 0, error_5xx: 0, error_rate: 0.0 }
          end

          req_count = buckets.sum(&:req_count)
          err_4xx   = buckets.sum(&:error_4xx)
          err_5xx   = buckets.sum(&:error_5xx)
          p95       = buckets.map(&:p95_ms).compact.max
          p50       = buckets.map(&:p50_ms).compact.max
          rpm       = (req_count.to_f / (WINDOW.to_f / 60)).round(2)
          error_rate = req_count.zero? ? 0.0 : (err_4xx + err_5xx).to_f / req_count

          {
            req_count: req_count, rpm: rpm,
            p50_ms: p50, p95_ms: p95,
            error_4xx: err_4xx, error_5xx: err_5xx,
            error_rate: error_rate
          }
        end

        def serialize_bucket(b)
          {
            bucket_start: b.bucket_start, req_count: b.req_count,
            p50_ms: b.p50_ms, p95_ms: b.p95_ms,
            error_4xx: b.error_4xx, error_5xx: b.error_5xx,
            bytes_sent_total: b.bytes_sent_total
          }
        end

        def recent_slow
          RequestSample
            .where(app_record_id: @app.id)
            .where("ts >= ?", 1.hour.ago)
            .where.not(response_time_ms: nil)
            .order(response_time_ms: :desc)
            .limit(SLOW_LIMIT)
        end

        def serialize_sample(s)
          {
            ts: s.ts, method: s.method, path: s.path,
            status: s.status, response_time_ms: s.response_time_ms,
            remote_addr: s.remote_addr
          }
        end
      end
    end
  end
end
