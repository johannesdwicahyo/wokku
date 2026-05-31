module Dashboard
  # Exposes the InvoiceCredit-backed referral system (shipped 1.7) as
  # its own dashboard page. Before 0.12 the only surface was an inline
  # strip on /dashboard/billing.
  class ReferralsController < BaseController
    def show
      @code = current_user.referral_promo_code || current_user.ensure_referral_promo_code!
      @signups       = @code.promo_redemptions.applied.count
      @pending       = @code.promo_redemptions.pending.count
      @bonus_per_ref = @code.inviter_bonus_idr
      @cash_earned   = @signups * @bonus_per_ref
      @share_url     = "#{request.base_url}/?code=#{@code.code}"
    end

    def regenerate
      current_user.referral_promo_code&.destroy
      current_user.ensure_referral_promo_code!
      redirect_to dashboard_referrals_path, notice: "New referral code generated."
    end
  end
end
