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
        counts = app.domains.filter_map { |d| host_requests[d.hostname] }
        next if counts.empty?

        total = counts.sum(&:to_i)
        next if app.request_count_seen == total

        app.update_columns(last_request_at: Time.current, request_count_seen: total)
      end
    end
  end
end
