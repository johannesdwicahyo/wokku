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
      next unless app.sleeping_tier?
      # A suspended owner's slept app could never wake (RunNotAllowed).
      next unless app.run_allowed?
      next if recently_deployed?(app)
      # Re-check right before stopping: a visit or a user stop landing
      # during a long serial sweep must win over the stale batch row.
      next unless AppRecord.running.where(id: app.id, last_request_at: ...IDLE_THRESHOLD.ago).exists?

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
