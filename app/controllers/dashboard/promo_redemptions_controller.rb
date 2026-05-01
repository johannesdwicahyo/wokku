module Dashboard
  class PromoRedemptionsController < BaseController
    def create
      result = PromoCodes::Redeem.call(user: current_user, code: params[:code])
      if result.ok?
        if result.promo_code.instant_grant?
          redirect_to dashboard_billing_path, notice: "Bonus Rp #{ActiveSupport::NumberHelper.number_to_delimited(result.promo_code.redeemer_bonus_idr, delimiter: '.')} sudah masuk ke saldo kamu."
        else
          redirect_to dashboard_billing_path, notice: "Kode tersimpan. Bonus akan masuk setelah top-up pertama kamu (min Rp #{ActiveSupport::NumberHelper.number_to_delimited(result.promo_code.min_deposit_idr, delimiter: '.')})."
        end
      else
        redirect_to dashboard_billing_path, alert: result.error
      end
    end
  end
end
