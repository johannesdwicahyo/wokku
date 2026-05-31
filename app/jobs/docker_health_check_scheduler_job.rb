# Fans out DockerHealthCheckJob across all servers. Recurring on the
# :health queue (same pool as HealthCheckScheduler). Skip-if-pending
# guard prevents pile-up when a host is unreachable.
class DockerHealthCheckSchedulerJob < ApplicationJob
  queue_as :health

  def perform
    server_count = Server.count
    cap = [ server_count * 2, 5 ].max

    pending = SolidQueue::Job.where(class_name: "DockerHealthCheckJob", finished_at: nil).count
    if pending >= cap
      Rails.logger.warn("DockerHealthCheckSchedulerJob: #{pending} pending >= cap #{cap}; skipping tick")
      return
    end

    Server.find_each { |s| DockerHealthCheckJob.perform_later(s.id) }
  end
end
