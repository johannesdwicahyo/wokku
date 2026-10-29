module Apps
  # Turns wokkud's per-hostname Caddy request counters (heartbeat
  # vitals["host_requests"], cumulative) into AppRecord#last_request_at —
  # the idle signal IdleCheckJob sleeps on. Any change in an app's summed
  # count is a visit; that includes a counter reset (Caddy restart) and the
  # first observation, which grants a fresh 30-minute grace. Deltas also go
  # into RequestAggregate buckets for 24h request counts.
  class VisitTracker
    def self.call(server, host_requests)
      return unless host_requests.is_a?(Hash) && host_requests.any?

      server.app_records.includes(:domains).find_each do |app|
        next if app.domains.empty?

        # Caddy emits a host only after its first request: absent = 0 since
        # Caddy started, or zero-traffic apps would never be observed/slept.
        total = app.domains.sum { |d| host_requests[d.hostname].to_i }
        seen = app.request_count_seen
        next if seen == total

        app.update_columns(last_request_at: Time.current, request_count_seen: total)
        # First observation has no baseline (the counter covers all of
        # Caddy's uptime), so it counts nothing; a reset counts from zero.
        record_requests(app, seen.nil? ? 0 : (total > seen ? total - seen : total))
      end
    end

    # Adds to the app's 5-minute request bucket, which feeds 24h totals.
    def self.record_requests(app, count)
      return unless count.positive?

      RequestAggregate.upsert(
        { app_record_id: app.id, bucket_start: RequestAggregate.bucket_for(Time.current), req_count: count },
        unique_by: :idx_req_agg_app_bucket,
        on_duplicate: Arel.sql("req_count = request_aggregates.req_count + EXCLUDED.req_count")
      )
    end
  end
end
