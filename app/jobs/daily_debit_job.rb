# Debits one user's deposit balance for yesterday's resource usage and
# suspends their apps if the balance drops to zero. The per-user logic
# lives in Billing::DailyDeduction; this job is just the scheduler hook
# + activity logging wrapper so one user failing doesn't break the rest
# of the nightly run.
class DailyDebitJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    record = Billing::DailyDeduction.new(user).process!
    return unless record

    Activity.log(
      user: user,
      team: user.teams.first,
      action: "billing.daily_debit",
      metadata: {
        channel: "system",
        amount: record[:amount],
        currency: record[:currency],
        date: record[:date].to_s,
        breakdown: record[:breakdown]
      }
    )

    # SleepAppsJob is already enqueued from Billing::DailyDeduction when
    # balance goes <= 0; mirror that into the activity feed so users see
    # why their apps stopped.
    if user.reload.balance <= 0 && user.billing_suspended?
      Activity.log(
        user: user, team: user.teams.first,
        action: "billing.app_suspended",
        metadata: { channel: "system", balance: user.balance }
      )
    end
  rescue StandardError => e
    Rails.logger.error("DailyDebitJob: user=#{user_id}: #{e.class}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end
end
