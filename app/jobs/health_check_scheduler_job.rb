class HealthCheckSchedulerJob < ApplicationJob
  def perform
    Server.find_each { |s| HealthCheckJob.perform_later(s.id) }
  end
end
