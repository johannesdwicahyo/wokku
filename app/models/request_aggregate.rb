# Per-app 5-minute request buckets. req_count is written by
# Apps::VisitTracker from Caddy's per-host counters in the heartbeat and
# read by the monitor page and 24h request stats. Latency/error columns
# came from the retired nginx-proxy sample rollup and stay empty.
#
# Unique on (app_record_id, bucket_start); VisitTracker upserts into it.
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
