class MetricsPollSchedulerJob < ApplicationJob
  # Polls every minute. If the previous tick hasn't fully drained, skip
  # this one rather than pile on. 3× server count gives slack for a
  # slow tick without letting the queue grow unbounded.
  def perform
    server_count = Server.count
    cap = [ server_count * 3, 10 ].max

    pending = SolidQueue::Job.where(class_name: "MetricsPollJob", finished_at: nil).count
    if pending >= cap
      Rails.logger.warn("MetricsPollSchedulerJob: #{pending} pending >= cap #{cap}; skipping tick")
      return
    end

    Server.find_each { |s| MetricsPollJob.perform_later(s.id) }
  end
end
