class UptimeCheckSchedulerJob < ApplicationJob
  # Page if this scheduler stops running (silent worker death), same
  # pattern as HealthCheckSchedulerJob. Cadence mirrors recurring.yml.
  include Sentry::Cron::MonitorCheckIns
  sentry_monitor_check_ins(
    slug: "uptime-check-scheduler",
    monitor_config: Sentry::Cron::MonitorConfig.from_crontab("* * * * *")
  )

  queue_as :uptime

  # Cap sized like HealthCheckSchedulerJob: transient network trouble must
  # not pile thousands of probe jobs behind a slow worker.
  def perform
    candidates = AppRecord.running.joins(:domains).distinct
    cap = [ candidates.count * 2, 20 ].max
    return if scheduler_saturated?("UptimeCheckJob", cap: cap)

    candidates.pluck(:id).each { |id| UptimeCheckJob.perform_later(id) }
  end
end
