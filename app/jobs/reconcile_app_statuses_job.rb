require "digest"

# Reconciles AppRecord#status (what the dashboard shows) against the Swarm
# task state the heartbeat fans out to app_records.live_containers, and
# Sentry-warns on drift. Writes only the running<->crashed pair; :stopped /
# :sleeping are intentional and never auto-flipped. A stale heartbeat
# (agent down) means we don't guess. Every app is on wokkud lifecycle since
# W7, so the old `docker ps` over SSH probe is gone.
class ReconcileAppStatusesJob < ApplicationJob
  queue_as :health

  def perform(server_id)
    server = Server.find_by(id: server_id)
    return unless server

    discrepancies = []

    # Flagged apps (B6 W4): status truth is the Swarm task state the
    # heartbeat fans out to app_records.live_containers — nothing else
    # writes their status post-adoption, so a crash-looping task showed
    # :running forever. Same running<->crashed pair only; a stale heartbeat
    # (agent down) means we don't guess.
    server.app_records.where(wokkud_lifecycle: true).find_each do |app|
      next if app.live_containers_at.nil? || app.live_containers_at < 10.minutes.ago
      # A worker-only app (web: 0, e.g. a bot) is alive on any running task.
      web_expected = ::Lifecycle::Ops.current_formation(app)["web"].to_i.positive?
      web_running = Array(app.live_containers).any? do |c|
        c["state"] == "running" && (!web_expected || c["process"] == "web")
      end
      status = app.status.to_s

      if status == "running" && !web_running
        app.update!(status: :crashed)
        discrepancies << "AppRecord #{app.id} (#{app.name}) status=running but no running web task -> :crashed"
      elsif status == "crashed" && web_running
        app.update!(status: :running)
        discrepancies << "AppRecord #{app.id} (#{app.name}) status=crashed but web task IS running -> :running"
      end
    end

    report_drift(server, discrepancies) if discrepancies.any?
  rescue StandardError => e
    Rails.logger.warn("ReconcileAppStatusesJob: #{server_id}: #{e.class}: #{e.message}")
    Sentry.capture_exception(e, level: :warning, extra: { server_id: server_id }) if defined?(Sentry)
  end

  private

  # Sentry-warn at most once per unique drift signature per server (6h TTL).
  # Without this, a persistent drift — e.g. the warn-only case where an
  # intentionally :stopped/:sleeping app still has a live container, which we
  # surface but deliberately never auto-flip — fires on every 10-min poll and
  # floods Sentry (it was 35% of all events). A changed drift set produces a
  # new signature and warns again; a stable one re-warns at most every 6h.
  def report_drift(server, discrepancies)
    summary = "ReconcileAppStatusesJob: #{discrepancies.size} drift(s) on #{server.name}"
    Rails.logger.warn(summary)

    signature = Digest::MD5.hexdigest(discrepancies.sort.join("|"))
    key = "reconcile:warned:#{server.id}:#{signature}"
    return if Rails.cache.read(key)

    Rails.cache.write(key, true, expires_in: 6.hours)
    discrepancies.first(10).each { |d| Rails.logger.warn("  - #{d}") }
    return unless defined?(Sentry)

    Sentry.capture_message(summary, level: :warning, extra: {
      server_id: server.id,
      server_name: server.name,
      discrepancies: discrepancies.first(30)
    })
  end
end
