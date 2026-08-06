class SyncServerSchedulerJob < ApplicationJob
  def perform
    cap = [ Server.count * 2, 5 ].max
    return if scheduler_saturated?("SyncServerJob", cap: cap)

    Server.find_each { |s| SyncServerJob.perform_later(s.id) }
  end
end
