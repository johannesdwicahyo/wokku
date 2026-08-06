# Fans out ReconcileAppStatusesJob across all servers. Every 10 min on
# the :health queue — frequent enough that drift surfaces fast, sparse
# enough that the SSH cost is negligible (one `docker ps` per server).
class ReconcileAppStatusesSchedulerJob < ApplicationJob
  queue_as :health

  def perform
    cap = [ Server.count * 2, 5 ].max
    return if scheduler_saturated?("ReconcileAppStatusesJob", cap: cap)

    Server.find_each { |s| ReconcileAppStatusesJob.perform_later(s.id) }
  end
end
