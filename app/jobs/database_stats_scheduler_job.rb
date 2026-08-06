# Every 5 min: enqueue DatabaseStatsCollectorJob for each
# postgres/redis service that's running. One enqueue per DB so a
# stuck SSH on one host doesn't block the rest.
class DatabaseStatsSchedulerJob < ApplicationJob
  queue_as :metrics

  def perform
    DatabaseService
      .where(service_type: DatabaseStatsCollectorJob::COLLECTORS.keys)
      .where(status: :running)
      .find_each do |db|
        DatabaseStatsCollectorJob.perform_later(db.id)
      end
  end
end
