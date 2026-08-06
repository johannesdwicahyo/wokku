module Api
  module V1
    module Serializers
      class AppMetrics
        MINUTE_LIMIT = 60
        HOURLY_LIMIT = 24

        def initialize(app)
          @app = app
        end

        def call
          {
            app_id: @app.id,
            minute: minute_rows,
            hourly: hourly_rows
          }
        end

        private

        def minute_rows
          rows = Metric
                   .where(app_record_id: @app.id)
                   .where.not(recorded_at: nil)
                   .order(recorded_at: :desc)
                   .limit(MINUTE_LIMIT)
                   .to_a
                   .reverse
          rows.map do |m|
            {
              ts: m.recorded_at,
              cpu_pct: m.cpu_percent,
              memory_mb: bytes_to_mb(m.memory_usage),
              memory_limit_mb: bytes_to_mb(m.memory_limit)
            }
          end
        end

        def hourly_rows
          rows = MetricHourly
                   .where(app_record_id: @app.id)
                   .order(hour_start: :desc)
                   .limit(HOURLY_LIMIT)
                   .to_a
                   .reverse
          rows.map do |m|
            {
              bucketed_at: m.hour_start,
              avg_cpu_pct: m.avg_cpu_percent,
              max_cpu_pct: m.max_cpu_percent,
              avg_memory_mb: bytes_to_mb(m.avg_memory_usage),
              max_memory_mb: bytes_to_mb(m.max_memory_usage),
              memory_limit_mb: bytes_to_mb(m.memory_limit),
              sample_count: m.sample_count
            }
          end
        end

        def bytes_to_mb(bytes)
          return nil if bytes.nil?
          (bytes.to_f / 1.megabyte).round(2)
        end
      end
    end
  end
end
