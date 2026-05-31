class SyncServerSchedulerJob < ApplicationJob
  def perform
    server_count = Server.count
    cap = [ server_count * 2, 5 ].max

    pending = SolidQueue::Job.where(class_name: "SyncServerJob", finished_at: nil).count
    if pending >= cap
      Rails.logger.warn("SyncServerSchedulerJob: #{pending} pending >= cap #{cap}; skipping tick")
      return
    end

    Server.find_each { |s| SyncServerJob.perform_later(s.id) }
  end
end
