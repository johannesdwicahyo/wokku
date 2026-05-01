# Fans out DailyDebitJob for every user that has at least one billable
# resource running. Scheduled daily at 01:00 UTC (08:00 WIB) via
# config/recurring.yml. Narrow scope = small failure surface; per-user
# errors are swallowed inside DailyDebitJob, so one bad user can't
# block the rest of the debit run.
class DailyDebitSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    scope = User.joins(:resource_usages)
                .merge(ResourceUsage.active.billable)
                .distinct
    count = 0
    scope.find_each do |user|
      DailyDebitJob.perform_later(user.id)
      count += 1
    end
    Rails.logger.info("DailyDebitSchedulerJob: enqueued #{count} user#{'s' unless count == 1}")
  end
end
