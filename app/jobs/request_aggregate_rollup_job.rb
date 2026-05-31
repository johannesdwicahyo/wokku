# Build a RequestAggregate row per (app, 5-min bucket) for every bucket
# touched since the last run, then prune samples older than the
# retention window (24h today; per-plan later). Idempotent via
# upsert on (app_record_id, bucket_start).
class RequestAggregateRollupJob < ApplicationJob
  queue_as :metrics

  # Used when an app has no resolvable owner plan (orphan / pre-1.9
  # apps from before the bundles seed). Matches the Free-tier setting.
  ORPHAN_SAMPLE_RETENTION_HOURS = 24
  ROLLUP_WINDOW = 30.minutes # cover gaps if the job was paused briefly

  def perform
    cutoff = Time.current - ROLLUP_WINDOW
    bucket_seconds = RequestAggregate::BUCKET_SECONDS

    # Group samples by (app_record_id, bucket). Postgres date_bin would
    # be ideal but isn't available pre-14; using TO_TIMESTAMP(floor)
    # works everywhere and keeps the job DB-portable.
    sql = <<~SQL.squish
      SELECT
        app_record_id,
        TO_TIMESTAMP(FLOOR(EXTRACT(EPOCH FROM ts) / #{bucket_seconds}) * #{bucket_seconds}) AS bucket_start,
        COUNT(*)                                                              AS req_count,
        PERCENTILE_DISC(0.5)  WITHIN GROUP (ORDER BY response_time_ms)        AS p50_ms,
        PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY response_time_ms)        AS p95_ms,
        SUM(CASE WHEN status >= 400 AND status < 500 THEN 1 ELSE 0 END)       AS error_4xx,
        SUM(CASE WHEN status >= 500 THEN 1 ELSE 0 END)                        AS error_5xx,
        COALESCE(SUM(bytes_sent), 0)                                          AS bytes_sent_total
      FROM request_samples
      WHERE app_record_id IS NOT NULL AND ts >= $1
      GROUP BY app_record_id, bucket_start
    SQL

    result = ActiveRecord::Base.connection.exec_query(sql, "RequestAggregateRollup", [ cutoff ])
    return if result.rows.empty?

    rows = result.to_a.map do |r|
      {
        app_record_id: r["app_record_id"],
        bucket_start: r["bucket_start"],
        req_count: r["req_count"].to_i,
        p50_ms: r["p50_ms"]&.to_i,
        p95_ms: r["p95_ms"]&.to_i,
        error_4xx: r["error_4xx"].to_i,
        error_5xx: r["error_5xx"].to_i,
        bytes_sent_total: r["bytes_sent_total"].to_i
      }
    end

    RequestAggregate.upsert_all(rows, unique_by: :idx_req_agg_app_bucket)

    prune_samples_per_plan
  end

  private

  # Walk apps that have any RequestSample rows and delete samples
  # older than that app's plan.sample_retention_hours window. Orphan
  # samples (app_record_id is nil) prune at ORPHAN_SAMPLE_RETENTION_HOURS.
  def prune_samples_per_plan
    app_ids_with_samples = RequestSample.where.not(app_record_id: nil).distinct.pluck(:app_record_id)
    AppRecord.where(id: app_ids_with_samples).includes(creator: :subscriptions).find_each do |app|
      cutoff = app.owner_plan.sample_retention_hours.hours.ago
      RequestSample.where(app_record_id: app.id).where("ts < ?", cutoff).delete_all
    end

    orphan_cutoff = ORPHAN_SAMPLE_RETENTION_HOURS.hours.ago
    RequestSample.where(app_record_id: nil).where("ts < ?", orphan_cutoff).delete_all
  end
end
