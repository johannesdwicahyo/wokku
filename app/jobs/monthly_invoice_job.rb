# Sends one PDF usage statement per user for the previous calendar month.
# Scheduled to run on the 1st of each month — see config/initializers/
# billing_jobs.rb. Idempotent within a calendar day: skips users already
# emailed for the period.
class MonthlyInvoiceJob < ApplicationJob
  include SentryMonitored
  monitor_with_sentry "monthly-invoice"
  queue_as :billing

  def perform(period_end: Date.current.beginning_of_month - 1.second)
    period_end = period_end.is_a?(Date) ? period_end.end_of_day : period_end
    period_start = period_end.beginning_of_month
    period_end_dt = period_end.end_of_month

    User.joins(:resource_usages)
        .where(resource_usages: { price_cents_per_hour: 0.0001.. })
        .where("resource_usages.started_at < ? AND (resource_usages.stopped_at IS NULL OR resource_usages.stopped_at > ?)",
               period_end_dt, period_start)
        .distinct
        .find_each do |user|
      send_for(user, period_start, period_end_dt)
    rescue StandardError => e
      Rails.logger.error("MonthlyInvoiceJob failed for user #{user.id}: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
    end
  end

  private

  def send_for(user, period_start, period_end)
    pdf = Billing::InvoicePdf.new(user, period_start: period_start, period_end: period_end)
    return if pdf.total_amount.to_i.zero? # skip $0 statements (free-tier-only users)

    BillingMailer.monthly_invoice(user, pdf, period_start, period_end).deliver_later
  end
end
