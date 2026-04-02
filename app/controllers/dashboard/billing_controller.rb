module Dashboard
  class BillingController < BaseController
    USD_TO_IDR = 16_000
    HOURS_PER_MONTH = 720

    def show
      @invoices = defined?(Invoice) ? Invoice.where(user: current_user).order(created_at: :desc).limit(12) : []
      @unpaid = @invoices.select { |i| i.respond_to?(:pending?) && i.pending? }

      period_start = Time.current.beginning_of_month
      period_end = Time.current.end_of_month
      now = Time.current

      # Hours elapsed and remaining in this billing period
      hours_elapsed = ((now - period_start) / 1.hour).round(1)
      hours_remaining = ((period_end - now) / 1.hour).round(1)
      hours_total = ((period_end - period_start) / 1.hour).round(1)

      # Calculate per-resource usage breakdown
      @dyno_items = []
      @addon_items = []
      current_total = 0.0
      projected_total = 0.0

      # Dyno costs from allocations
      if defined?(DynoAllocation)
        apps = policy_scope(AppRecord).includes(dyno_allocations: :dyno_tier)
        apps.each do |app|
          app.dyno_allocations.each do |alloc|
            tier = alloc.dyno_tier
            hourly_rate = tier.price_cents_per_hour.to_f
            next if hourly_rate <= 0

            # Each dyno count × hours elapsed
            current_cost = (alloc.count * hourly_rate * hours_elapsed / 100.0).round(2)
            monthly_cap = tier.monthly_price_dollars * alloc.count
            current_cost = [current_cost, monthly_cap].min

            projected_cost = [alloc.count * hourly_rate * hours_total / 100.0, monthly_cap].min.round(2)

            @dyno_items << {
              name: app.name,
              process_type: alloc.process_type,
              tier: tier.name,
              count: alloc.count,
              hourly_rate: hourly_rate,
              hours: hours_elapsed,
              current_cost: current_cost,
              projected_cost: projected_cost,
              monthly_cap: monthly_cap
            }

            current_total += current_cost
            projected_total += projected_cost
          end
        end
      end

      # Add-on costs from resource usages
      if defined?(ResourceUsage)
        ResourceUsage.where(user: current_user).active.where("price_cents_per_hour > 0").each do |usage|
          hourly_rate = usage.price_cents_per_hour.to_f
          current_cost = (hourly_rate * hours_elapsed / 100.0).round(2)
          projected_cost = (hourly_rate * hours_total / 100.0).round(2)

          @addon_items << {
            name: usage.metadata.is_a?(String) ? (JSON.parse(usage.metadata)["name"] rescue usage.resource_id_ref) : (usage.metadata&.dig("name") || usage.resource_id_ref),
            tier: usage.tier_name,
            type: usage.resource_type,
            hourly_rate: hourly_rate,
            hours: hours_elapsed,
            current_cost: current_cost,
            projected_cost: projected_cost
          }

          current_total += current_cost
          projected_total += projected_cost
        end
      end

      @billing = {
        current_total: current_total.round(2),
        projected_total: projected_total.round(2),
        current_idr: (current_total * USD_TO_IDR).round,
        projected_idr: (projected_total * USD_TO_IDR).round,
        hours_elapsed: hours_elapsed,
        hours_remaining: hours_remaining,
        hours_total: hours_total,
        period_progress: ((hours_elapsed / hours_total) * 100).round(1),
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
