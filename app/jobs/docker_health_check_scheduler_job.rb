# Fans out DockerHealthCheckJob across all servers. Recurring on the
# :health queue (same pool as HealthCheckScheduler). Skip-if-pending
# guard prevents pile-up when a host is unreachable.
class DockerHealthCheckSchedulerJob < ApplicationJob
  queue_as :health

  def perform
    cap = [ Server.count * 2, 5 ].max
    return if scheduler_saturated?("DockerHealthCheckJob", cap: cap)

    Server.find_each { |s| DockerHealthCheckJob.perform_later(s.id) }
  end
end
