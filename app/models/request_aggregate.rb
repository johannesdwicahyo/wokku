# 5-minute roll-up of RequestSample for one app. Built by
# RequestAggregateRollupJob every 5 min, then queried by the per-app
# monitor page for charts (req-rate, p50/p95, error %).
#
# Unique on (app_record_id, bucket_start) so the rollup is idempotent
# — re-running the job for the same bucket is a no-op via upsert.
class RequestAggregate < ApplicationRecord
  belongs_to :app_record

  BUCKET_SECONDS = 5 * 60

  scope :for_app, ->(app) { where(app_record_id: app.id) }
  scope :since,   ->(t)   { where("bucket_start >= ?", t) }
  scope :recent,  -> { order(bucket_start: :desc) }
  scope :asc_t,   -> { order(bucket_start: :asc) }

  def self.bucket_for(time)
    Time.at((time.to_i / BUCKET_SECONDS) * BUCKET_SECONDS).utc
  end

  def error_total
    error_4xx + error_5xx
  end

  def error_rate
    return 0.0 if req_count.zero?
    error_total.to_f / req_count
  end
end
