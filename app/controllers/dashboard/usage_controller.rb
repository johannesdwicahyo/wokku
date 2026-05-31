module Dashboard
  # Railway-style usage page: shows trial state, next invoice estimate,
  # plan included resources, and per-app share of the plan price.
  #
  # Under Phase 4 invoice billing, "usage" is mostly about helping the
  # user understand what their plan covers + when the next charge lands.
  # No more per-hour metering.
  class UsageController < BaseController
    def show
      @plan = current_user.plan
      @on_trial = current_user.on_trial?
      @trial_ends_at = current_user.trial_ends_at
      @trial_days_left = @on_trial ? ((@trial_ends_at.to_date - Date.current).to_i) : 0
      @next_billing_date = current_user.next_billing_date
      @next_invoice_amount_idr = @plan.free? ? 0 : @plan.price_idr.to_i
      @paid_invoices_count = current_user.invoices.paid.count
      @upcoming_unpaid = current_user.invoices.unpaid.order(:due_date).first
      @pending_credits = InvoiceCredit.unapplied.for_user(current_user)
      @pending_credit_total = @pending_credits.sum(:amount_idr)
      @next_invoice_after_credits = [ @next_invoice_amount_idr - @pending_credit_total, 0 ].max

      @apps = current_user.app_records.order(created_at: :desc)
      @box_quotas = @plan.box_quotas || {}
      @box_usage = compute_box_usage(@apps)
      @bundle_usage = compute_bundle_usage
    end

    private

    def compute_box_usage(apps)
      usage = Hash.new(0)
      apps.each do |app|
        app.dyno_allocations.includes(:dyno_tier).each do |alloc|
          size = alloc.dyno_tier&.size_key
          usage[size] += alloc.count if size
        end
      end
      usage
    end

    # Per-resource usage for the bundle utilization card. Postgres
    # counts how many DBs the user owns (1 of 1 included). Live
    # storage-MB tracking is the SharedDatabaseQuotaJob's job; not
    # surfaced here yet because the plugin reports it but the column
    # isn't persisted in v1.
    def compute_bundle_usage
      {
        db_count: DatabaseService.where(creator: current_user, service_type: "postgres").count,
        redis_count: DatabaseService.where(creator: current_user, service_type: "redis").count,
        minio_count: 0
      }
    end
  end
end
