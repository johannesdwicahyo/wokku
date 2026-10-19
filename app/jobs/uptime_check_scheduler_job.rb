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
    # Sleeping-tier apps are skipped: a probe every minute would count as a
    # visit and keep them awake forever (wake-on-request, 2026-10-19).
    candidates = AppRecord.running.joins(:domains).distinct
      .where.not(id: DynoAllocation.joins(:dyno_tier)
        .where(process_type: "web", cpu: nil, dyno_tiers: { sleeps: true }).select(:app_record_id))
    cap = [ candidates.count * 2, 20 ].max
    return if scheduler_saturated?("UptimeCheckJob", cap: cap)

    candidates.pluck(:id).each { |id| UptimeCheckJob.perform_later(id) }
  end
end
