# Fans out StaleDeployLockJob across connected servers every 10 min.
class StaleDeployLockSchedulerJob < ApplicationJob
  queue_as :health

  def perform
    cap = [ Server.count * 2, 5 ].max
    return if scheduler_saturated?("StaleDeployLockJob", cap: cap)

    Server.where(status: :connected).find_each { |s| StaleDeployLockJob.perform_later(s.id) }
  end
end
