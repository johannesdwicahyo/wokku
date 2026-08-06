# Fans out CrashLoopDetectorJob across connected servers every 2 min on
# the :health queue — one `docker ps -a` per server, cheap.
class CrashLoopDetectorSchedulerJob < ApplicationJob
  queue_as :health

  def perform
    cap = [ Server.count * 2, 5 ].max
    return if scheduler_saturated?("CrashLoopDetectorJob", cap: cap)

    Server.where(status: :connected).find_each { |s| CrashLoopDetectorJob.perform_later(s.id) }
  end
end
