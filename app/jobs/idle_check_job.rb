# Sleeps free apps nobody has visited for IDLE_THRESHOLD (wake-on-request,
# 2026-10-19). Visits come from Caddy's per-host counters via the heartbeat
# (Apps::VisitTracker); an app with no observation yet (nil) is never slept.
# Any request to a sleeping app wakes it (WakeController → WakeAppJob).
class IdleCheckJob < ApplicationJob
  queue_as :default

  IDLE_THRESHOLD = 30.minutes

  def perform
    AppRecord.running.where(last_request_at: ...IDLE_THRESHOLD.ago)
      .includes(dyno_allocations: :dyno_tier).find_each do |app|
      next unless app.dyno_allocations.find { |a| a.process_type == "web" }&.sleeping?
      next if recently_deployed?(app)

      Lifecycle::Ops.converge!(app, formation: Lifecycle::Ops.stop_formation(app), allow_empty: true)
      app.sleeping!
    rescue StandardError => e
      Rails.logger.warn("IdleCheckJob: Failed to sleep #{app.name}: #{e.message}")
      Sentry.capture_exception(e, extra: { app: app.name }) if defined?(Sentry)
    end
  end

  private

  def recently_deployed?(app)
    app.deploys.where(status: :succeeded).where("finished_at > ?", IDLE_THRESHOLD.ago).exists?
  end
end
