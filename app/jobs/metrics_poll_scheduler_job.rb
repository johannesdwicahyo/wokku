class MetricsPollSchedulerJob < ApplicationJob
  # Polls every minute. If the previous tick hasn't fully drained, skip
  # this one rather than pile on. 3× server count gives slack for a
  # slow tick without letting the queue grow unbounded.
  def perform
    cap = [ Server.count * 3, 10 ].max
    return if scheduler_saturated?("MetricsPollJob", cap: cap)

    Server.find_each { |s| MetricsPollJob.perform_later(s.id) }
  end
end
