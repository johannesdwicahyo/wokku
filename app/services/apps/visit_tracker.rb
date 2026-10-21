module Apps
  # Turns wokkud's per-hostname Caddy request counters (heartbeat
  # vitals["host_requests"], cumulative) into AppRecord#last_request_at —
  # the idle signal IdleCheckJob sleeps on. Any change in an app's summed
  # count is a visit; that includes a counter reset (Caddy restart) and the
  # first observation, which grants a fresh 30-minute grace.
  class VisitTracker
    def self.call(server, host_requests)
      return unless host_requests.is_a?(Hash) && host_requests.any?

      server.app_records.includes(:domains).find_each do |app|
        next if app.domains.empty?

        # Caddy emits a host only after its first request: absent = 0 since
        # Caddy started, or zero-traffic apps would never be observed/slept.
        total = app.domains.sum { |d| host_requests[d.hostname].to_i }
        next if app.request_count_seen == total

        app.update_columns(last_request_at: Time.current, request_count_seen: total)
      end
    end
  end
end
