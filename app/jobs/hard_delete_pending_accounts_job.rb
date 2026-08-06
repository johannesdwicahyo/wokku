# Scheduled daily (config/recurring.yml). Finds all users whose 3-day
# grace period has elapsed and enqueues HardDeleteAccountJob for each.
class HardDeletePendingAccountsJob < ApplicationJob
  queue_as :default

  def perform
    User.ready_for_hard_delete.find_each do |user|
      HardDeleteAccountJob.perform_later(user.id)
    end
  end
end
