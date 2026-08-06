class ScheduledTaskRunPruneJob < ApplicationJob
  queue_as :default

  def perform
    ScheduledTaskRun.prune!
  end
end
