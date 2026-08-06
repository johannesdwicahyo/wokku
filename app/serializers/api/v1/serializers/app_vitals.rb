module Api
  module V1
    module Serializers
      class AppVitals
        WINDOW = 7.days
        METRICS = VitalsEvent::METRICS

        def initialize(app)
          @app = app
        end

        def call
          rollups = VitalsHourlyRollup
                     .where(app_record_id: @app.id)
                     .where("bucketed_at >= ?", WINDOW.ago.beginning_of_hour)
                     .order(:bucketed_at)
                     .to_a

          history = METRICS.index_with { |_| [] }
          rollups.each do |r|
            history[r.metric] << {
              bucketed_at: r.bucketed_at,
              p50: r.p50, p75: r.p75, p95: r.p95,
              sample_count: r.sample_count
            }
          end

          latest = METRICS.index_with do |metric|
            last = history[metric].last
            next nil unless last
            { p50: last[:p50], p75: last[:p75], p95: last[:p95],
              sample_count: last[:sample_count], bucketed_at: last[:bucketed_at] }
          end

          {
            app_id: @app.id,
            window_days: WINDOW.to_i / 1.day.to_i,
            latest: latest,
            history: history
          }
        end
      end
    end
  end
end
