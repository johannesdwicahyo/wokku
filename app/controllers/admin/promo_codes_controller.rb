module Admin
  class PromoCodesController < BaseController
    UUID_RE = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    def index
      scope = PromoCode.where(kind: %w[manual_credit channel_match])
      if params[:batch_id].to_s.match?(UUID_RE)
        scope = scope.where(batch_id: params[:batch_id])
        @batch_id = params[:batch_id]
        @batch_label = scope.pick(:batch_label)
      end
      @codes = scope.order(created_at: :desc).includes(:created_by)
    end

    def create
      kind = params[:kind].to_s
      return redirect_to admin_promo_codes_path, alert: "Invalid kind." unless %w[manual_credit channel_match].include?(kind)

      attrs = {
        code: params[:code].to_s.strip.upcase,
        kind: kind,
        redeemer_bonus_idr: params[:redeemer_bonus_idr].to_i,
        inviter_bonus_idr: 0,
        max_redemptions: params[:max_redemptions].presence&.to_i,
        description: params[:description].to_s.presence,
        created_by: current_user
      }

      promo = PromoCode.new(attrs)
      if promo.save
        redirect_to admin_promo_codes_path, notice: "Kode #{promo.code} dibuat."
      else
        redirect_to admin_promo_codes_path, alert: promo.errors.full_messages.to_sentence
      end
    end

    def new_batch
    end

    def create_batch
      result = PromoCodes::GenerateBatch.call(
        count: params[:count].to_i,
        prefix: params[:prefix].to_s,
        batch_label: params[:batch_label].to_s,
        kind: params[:kind].to_s,
        redeemer_bonus_idr: params[:redeemer_bonus_idr].to_i,
        inviter_bonus_idr: 0,
        expires_at: nil,
        description: params[:description].to_s.presence,
        created_by: current_user
      )

      if result.ok?
        redirect_to admin_promo_codes_path(batch_id: result.batch_id),
                    notice: "Generated #{result.codes.size} vouchers."
      else
        redirect_to new_batch_admin_promo_codes_path, alert: result.error
      end
    end

    def destroy
      promo = PromoCode.find(params[:id])
      return redirect_to admin_promo_codes_path, alert: "Referral codes can't be deleted from here." if promo.referral?

      promo.update!(active: false)
      redirect_to admin_promo_codes_path, notice: "Kode #{promo.code} dinonaktifkan."
    end
  end
end
