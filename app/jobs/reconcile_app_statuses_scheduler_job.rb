# Fans out ReconcileAppStatusesJob across all servers. Every 10 min on
# the :health queue — frequent enough that drift surfaces fast, sparse
# enough that the SSH cost is negligible (one `docker ps` per server).
class ReconcileAppStatusesSchedulerJob < ApplicationJob
  queue_as :health

  def perform
    server_count = Server.count
    cap = [ server_count * 2, 5 ].max

    pending = SolidQueue::Job.where(class_name: "ReconcileAppStatusesJob", finished_at: nil).count
    if pending >= cap
      Rails.logger.warn("ReconcileAppStatusesSchedulerJob: #{pending} pending >= cap #{cap}; skipping tick")
      return
    end

    Server.find_each { |s| ReconcileAppStatusesJob.perform_later(s.id) }
  end
end
