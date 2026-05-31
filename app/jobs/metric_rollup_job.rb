# Daily rollup of the high-resolution `metrics` table into hourly
# `metric_hourly` buckets. Per the bundles spec, each plan defines:
#   - plan.metric_high_res_days — keep raw 1-min Metric rows that long
#   - plan.metric_aggregate_retention_days — keep MetricHourly rows that long
#
# Each pass, for every app:
#   1. Aggregate Metric rows older than `metric_high_res_days` into
#      hourly buckets via upsert on (app_record_id, hour_start).
#   2. Delete the source Metric rows once their data is in a bucket.
#   3. Delete MetricHourly rows older than `metric_aggregate_retention_days`.
#
# Step 1 + 2 are split-and-loop (not a single SQL) so the upsert and
# delete share an identical row set. If a new Metric row lands between
# them it's older than the cutoff (by definition) and the next pass
# rolls it up.
class MetricRollupJob < ApplicationJob
  queue_as :metrics

  ORPHAN_HIGH_RES_DAYS = 1
  ORPHAN_AGG_RETENTION_DAYS = 7

  def perform
    rolled_up = 0
    AppRecord.includes(creator: :subscriptions).find_each do |app|
      plan = app.owner_plan
      rolled_up += rollup_for(app, plan.metric_high_res_days)
      MetricHourly.where(app_record_id: app.id)
                  .where("hour_start < ?", plan.metric_aggregate_retention_days.days.ago)
                  .delete_all
    end

    # Orphans (Metric rows whose app was deleted but the row lingered):
    Metric.where.missing(:app_record).where("recorded_at < ?", ORPHAN_HIGH_RES_DAYS.days.ago).delete_all
    MetricHourly.where.missing(:app_record).where("hour_start < ?", ORPHAN_AGG_RETENTION_DAYS.days.ago).delete_all

    Rails.logger.info "MetricRollupJob: aggregated #{rolled_up} buckets across all apps"
    { aggregated: rolled_up }
  end

  private

  def rollup_for(app, high_res_days)
    cutoff = high_res_days.days.ago
    return 0 unless Metric.where(app_record_id: app.id).where("recorded_at < ?", cutoff).exists?

    sql = <<~SQL.squish
      SELECT
        DATE_TRUNC('hour', recorded_at)               AS hour_start,
        AVG(cpu_percent)                              AS avg_cpu,
        MAX(cpu_percent)                              AS max_cpu,
        AVG(memory_usage)                             AS avg_mem,
        MAX(memory_usage)                             AS max_mem,
        MAX(memory_limit)                             AS limit_last,
        COUNT(*)                                      AS sample_count
      FROM metrics
      WHERE app_record_id = $1 AND recorded_at < $2
      GROUP BY hour_start
    SQL

    result = ActiveRecord::Base.connection.exec_query(sql, "MetricRollup", [ app.id, cutoff ])
    return 0 if result.rows.empty?

    rows = result.to_a.map do |r|
      {
        app_record_id: app.id,
        hour_start: r["hour_start"],
        avg_cpu_percent: r["avg_cpu"],
        max_cpu_percent: r["max_cpu"],
        avg_memory_usage: r["avg_mem"]&.to_i,
        max_memory_usage: r["max_mem"]&.to_i,
        memory_limit: r["limit_last"]&.to_i,
        sample_count: r["sample_count"].to_i
      }
    end

    MetricHourly.upsert_all(rows, unique_by: :idx_metric_hourly_app_hour)
    Metric.where(app_record_id: app.id).where("recorded_at < ?", cutoff).delete_all
    rows.size
  end
end
