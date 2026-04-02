class MonthlyBillingJob < ApplicationJob
  queue_as :billing

  USD_TO_IDR = 16_000

  def perform
    period_start = 1.month.ago.beginning_of_month
    period_end = 1.month.ago.end_of_month
    period_label = period_start.strftime("%B %Y")

    User.find_each do |user|
      next if user.admin?

      usages = ResourceUsage.where(user: user).in_period(period_start, period_end)
      total_cents = usages.sum { |u| u.cost_cents_in_period(period_start, period_end) }.round

      next if total_cents <= 0

      ref = "INV-#{user.id}-#{period_start.strftime('%Y%m')}"
      next if Invoice.exists?(reference_id: ref)

      amount_idr = (total_cents * USD_TO_IDR / 100.0).round

      invoice = Invoice.create!(
        user: user,
        amount_cents: total_cents,
        amount_idr: amount_idr,
        reference_id: ref,
        period_label: period_label,
        due_date: Time.current + 3.days,
        status: :pending
      )

      client = IpaymuClient.new
      result = client.create_redirect_payment(
        amount_idr: amount_idr,
        reference_id: ref,
        products: [ "Wokku #{period_label} - #{user.email}" ]
      )

      if result["Status"] == 200 && result["Data"]
        invoice.update!(
          ipaymu_payment_url: result["Data"]["Url"],
          ipaymu_transaction_id: result["Data"]["SessionID"]
        )
      else
        Rails.logger.error "iPaymu payment creation failed for #{ref}: #{result}"
      end
    end
  end
end
