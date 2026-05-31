module Admin
  # Admin-only metrics dashboard. Single Rails query per metric — none
  # of these scan more than the deposit / user / app tables, so the
  # whole page renders in <100ms even at 10k users.
  class DashboardController < BaseController
    def index
      @today_start  = Time.zone.now.beginning_of_day
      @month_start  = Time.zone.now.beginning_of_month
      @week_start   = 7.days.ago.beginning_of_day

      @revenue = revenue_metrics
      @users   = user_metrics
      @apps    = app_metrics
      @promos  = promo_metrics
    end

    private

    def revenue_metrics
      # Phase 4: real money in = paid invoices. Replaces the
      # DepositTransaction-based metric (removed in 1.8).
      base = Invoice.paid.where("amount_idr > 0")
      {
        today_idr:     base.where(paid_at: @today_start..).sum(:amount_idr),
        mtd_idr:       base.where(paid_at: @month_start..).sum(:amount_idr),
        all_time_idr:  base.sum(:amount_idr),
        unique_payers: base.distinct.count(:user_id)
      }
    end

    def user_metrics
      {
        total:         User.count,
        new_today:     User.where(created_at: @today_start..).count,
        new_this_week: User.where(created_at: @week_start..).count,
        on_trial:      User.where("trial_ends_at > ?", Time.current).count
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
