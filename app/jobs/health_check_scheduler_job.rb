class HealthCheckSchedulerJob < ApplicationJob
  # Cap to keep a transient SSH outage from spawning thousands of stuck
  # HealthCheckJobs. If more than (servers × 2) are still ready, the
  # worker is behind — skip this tick and let it drain instead of piling
  # on. Sized at 2× server count to allow one in-flight + one queued
  # per host comfortably.
  def perform
    server_count = Server.count
    cap = [ server_count * 2, 10 ].max

    pending = SolidQueue::Job.where(class_name: "HealthCheckJob", finished_at: nil).count
    if pending >= cap
      Rails.logger.warn("HealthCheckSchedulerJob: #{pending} pending >= cap #{cap}; skipping tick")
      return
    end

    Server.find_each { |s| HealthCheckJob.perform_later(s.id) }
  end
end
