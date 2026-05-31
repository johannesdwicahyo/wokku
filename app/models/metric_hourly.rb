# Hourly roll-up of Metric rows (one row per (app, hour)). Built by
# MetricRollupJob daily — for each app, aggregates raw Metric rows
# older than `plan.metric_high_res_days` into hourly buckets and
# deletes the source rows.
#
# Retention of MetricHourly rows itself is `plan.metric_aggregate_retention_days`.
class MetricHourly < ApplicationRecord
  self.table_name = "metric_hourly"

  belongs_to :app_record

  scope :for_app, ->(app) { where(app_record_id: app.id) }
  scope :since,   ->(t)   { where("hour_start >= ?", t) }
  scope :recent,  -> { order(hour_start: :desc) }

  def self.bucket_for(time)
    Time.utc(time.year, time.month, time.day, time.hour)
  end
end
