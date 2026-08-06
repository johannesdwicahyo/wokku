class HealthCheckSchedulerJob < ApplicationJob
  # Page if this scheduler stops running (silent worker/box death), not
  # only if it errors. Cadence mirrors config/recurring.yml (every 5 min).
  include Sentry::Cron::MonitorCheckIns
  sentry_monitor_check_ins(
    slug: "health-check-scheduler",
    monitor_config: Sentry::Cron::MonitorConfig.from_crontab("*/5 * * * *")
  )

  # Cap to keep a transient SSH outage from spawning thousands of stuck
  # HealthCheckJobs. If more than (servers × 2) are still ready, the
  # worker is behind — skip this tick and let it drain instead of piling
  # on. Sized at 2× server count to allow one in-flight + one queued
  # per host comfortably.
  def perform
    cap = [ Server.count * 2, 10 ].max
    return if scheduler_saturated?("HealthCheckJob", cap: cap)

    Server.find_each { |s| HealthCheckJob.perform_later(s.id) }
  end
end
