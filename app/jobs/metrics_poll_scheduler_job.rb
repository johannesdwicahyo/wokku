class MetricsPollSchedulerJob < ApplicationJob
  def perform
    Server.find_each { |s| MetricsPollJob.perform_later(s.id) }
  end
end
