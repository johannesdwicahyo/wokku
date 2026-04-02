module Dashboard
  class BillingController < BaseController
    USD_TO_IDR = 16_000

    def show
      @invoices = defined?(Invoice) ? Invoice.where(user: current_user).order(created_at: :desc).limit(12) : []
      @unpaid = @invoices.select { |i| i.respond_to?(:pending?) && i.pending? }

      period_start = Time.current.beginning_of_month
      period_end = Time.current
      usages = defined?(ResourceUsage) ? ResourceUsage.where(user: current_user).where("started_at < ? AND (stopped_at IS NULL OR stopped_at > ?)", period_end, period_start) : []
      total_cents = usages.sum { |u| u.cost_cents_in_period(period_start, period_end) }.round rescue 0

      @current_usage = {
        total_cents: total_cents,
        total_dollars: total_cents / 100.0,
        total_idr: (total_cents * USD_TO_IDR / 100.0).round,
        period: "#{period_start.strftime('%b %d')} - #{period_end.strftime('%b %d, %Y')}"
      }
    end

    def pay
      invoice = Invoice.find(params[:id])
      return redirect_to dashboard_billing_path, alert: "Not authorized" unless invoice.user_id == current_user.id

      if invoice.ipaymu_payment_url.present?
        redirect_to invoice.ipaymu_payment_url, allow_other_host: true
      else
        client = IpaymuClient.new
        result = client.create_redirect_payment(
          amount_idr: invoice.amount_idr,
          reference_id: invoice.reference_id,
          products: ["Wokku #{invoice.period_label} - #{current_user.email}"]
        )
        if result["Status"] == 200 && result["Data"]
          invoice.update!(ipaymu_payment_url: result["Data"]["Url"])
          redirect_to result["Data"]["Url"], allow_other_host: true
        else
          redirect_to dashboard_billing_path, alert: "Payment creation failed."
        end
      end
    end
  end
end
