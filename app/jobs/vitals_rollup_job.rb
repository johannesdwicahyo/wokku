# Roll raw VitalsEvent rows into hourly p50/p75/p95 per (app, metric).
# Runs every 5 minutes via config/recurring.yml. Only processes hours that
# are fully in the past (i.e., the current hour stays open until it ends).
# After the rollup pass, prunes events older than 25 hours.
class VitalsRollupJob < ApplicationJob
  queue_as :metrics

  TTL = 25.hours

  def perform
    current_hour_start = Time.current.beginning_of_hour
    cutoff             = current_hour_start - 6.hours # cover gaps from missed runs

    sql = <<~SQL.squish
      SELECT
        app_record_id,
        DATE_TRUNC('hour', received_at)                                 AS bucketed_at,
        metric,
        PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY value_ms)          AS p50,
        PERCENTILE_DISC(0.75) WITHIN GROUP (ORDER BY value_ms)          AS p75,
        PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY value_ms)          AS p95,
        COUNT(*)                                                        AS sample_count
      FROM vitals_events
      WHERE received_at >= $1 AND received_at < $2
      GROUP BY app_record_id, bucketed_at, metric
    SQL

    result = ActiveRecord::Base.connection.exec_query(
      sql, "VitalsRollup", [ cutoff, current_hour_start ]
    )

    rows = result.to_a.map do |r|
      {
        app_record_id: r["app_record_id"],
        bucketed_at:   r["bucketed_at"],
        metric:        r["metric"],
        p50:           r["p50"].to_f,
        p75:           r["p75"].to_f,
        p95:           r["p95"].to_f,
        sample_count:  r["sample_count"].to_i
      }
    end

    if rows.any?
      VitalsHourlyRollup.upsert_all(rows, unique_by: :idx_vitals_rollup_unique)
    end

    VitalsEvent.where("received_at < ?", TTL.ago).delete_all
  end
end
