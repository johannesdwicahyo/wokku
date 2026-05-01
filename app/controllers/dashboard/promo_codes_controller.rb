module Dashboard
  class PromoCodesController < BaseController
    before_action :require_admin!

    def index
      @codes = PromoCode.where(kind: %w[manual_credit channel_match])
                        .order(created_at: :desc)
                        .includes(:created_by)
    end

    def create
      kind = params[:kind].to_s
      return redirect_to dashboard_promo_codes_path, alert: "Invalid kind." unless %w[manual_credit channel_match].include?(kind)

      attrs = {
        code: params[:code].to_s.strip.upcase,
        kind: kind,
        redeemer_bonus_idr: params[:redeemer_bonus_idr].to_i,
        inviter_bonus_idr: 0,
        min_deposit_idr: kind == "channel_match" ? params[:min_deposit_idr].to_i : 0,
        max_redemptions: params[:max_redemptions].presence&.to_i,
        description: params[:description].to_s.presence,
        created_by: current_user
      }

      promo = PromoCode.new(attrs)
      if promo.save
        redirect_to dashboard_promo_codes_path, notice: "Kode #{promo.code} dibuat."
      else
        redirect_to dashboard_promo_codes_path, alert: promo.errors.full_messages.to_sentence
      end
    end

    def destroy
      promo = PromoCode.find(params[:id])
      return redirect_to dashboard_promo_codes_path, alert: "Referral codes can't be deleted from here." if promo.referral?

      promo.update!(active: false)
      redirect_to dashboard_promo_codes_path, notice: "Kode #{promo.code} dinonaktifkan."
    end

    private

    def require_admin!
      redirect_to dashboard_root_path, alert: "Admin only." unless current_user&.admin?
    end
  end
end
