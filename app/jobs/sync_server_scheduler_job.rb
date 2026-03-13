class SyncServerSchedulerJob < ApplicationJob
  def perform
    Server.find_each { |s| SyncServerJob.perform_later(s.id) }
  end
end
