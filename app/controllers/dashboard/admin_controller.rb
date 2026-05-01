module Dashboard
  # Admin-only metrics dashboard. Single Rails query per metric — none
  # of these scan more than the deposit / user / app tables, so the
  # whole page renders in <100ms even at 10k users.
  class AdminController < BaseController
    before_action :require_admin!

    def show
      @today_start  = Time.zone.now.beginning_of_day
      @month_start  = Time.zone.now.beginning_of_month
      @week_start   = 7.days.ago.beginning_of_day

      @revenue = revenue_metrics
      @users   = user_metrics
      @apps    = app_metrics
      @promos  = promo_metrics
    end

    private

    def require_admin!
      redirect_to dashboard_root_path, alert: "Admin only." unless current_user&.admin?
    end

    def revenue_metrics
      # Real money in: completed iPaymu / Stripe deposits. Excludes
      # `manual` (admin-issued credit + promo bonus payouts) so a
      # generous code redemption doesn't inflate "today's revenue".
      # IDR rupiah and USD cents are different units — sum each side
      # separately, convert USD to IDR via the canonical helper, then
      # add. No merging of scopes (was double-counting).
      base = DepositTransaction.completed.where("amount > 0").where.not(payment_gateway: "manual")
      sum_idr = ->(scope) {
        idr_total       = scope.where(currency: "idr").sum(:amount).to_i
        usd_cents_total = scope.where(currency: "usd").sum(:amount).to_i
        idr_total + Billing::Money.to_currency(usd_cents_total, currency: "idr")
      }
      {
        today_idr:    sum_idr.call(base.where(created_at: @today_start..)),
        mtd_idr:      sum_idr.call(base.where(created_at: @month_start..)),
        all_time_idr: sum_idr.call(base),
        unique_payers: base.distinct.count(:user_id)
      }
    end

    def user_metrics
      {
        total:        User.count,
        new_today:    User.where(created_at: @today_start..).count,
        new_this_week: User.where(created_at: @week_start..).count,
        with_balance: User.where("balance_idr > 0 OR balance_usd_cents > 0").count
      }
    end

    def app_metrics
      apps = AppRecord
      {
        total:       apps.count,
        running:     apps.where(status: :running).count,
        new_today:   apps.where(created_at: @today_start..).count,
        servers:     Server.count
      }
    end

    def promo_metrics
      {
        pending: PromoRedemption.pending.count,
        applied_total: PromoRedemption.applied.count,
        applied_today: PromoRedemption.applied.where(applied_at: @today_start..).count,
        # Per-code attribution: which channel converted? Sort by applied
        # count, descending. Hides referral codes — those are per-user
        # and noisy here.
        top_codes: PromoCode.where(kind: %w[manual_credit channel_match])
                            .select("promo_codes.*, redemptions_count AS rc")
                            .order("redemptions_count DESC")
                            .limit(10)
      }
    end
  end
end
