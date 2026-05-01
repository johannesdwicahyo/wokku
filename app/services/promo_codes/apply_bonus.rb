module PromoCodes
  # Pays out a redemption: writes a `manual` DepositTransaction for each
  # side (so the bonus shows up in the user's existing ledger / CSV
  # export with no special-case rendering) and bumps balance_idr.
  #
  # Idempotent at the row level — once a redemption is applied it won't
  # be applied again. Safe to retry from the iPaymu webhook.
  class ApplyBonus
    Result = Struct.new(:ok?, :error, keyword_init: true)

    def self.call(redemption:, deposit:)
      new(redemption: redemption, deposit: deposit).call
    end

    def initialize(redemption:, deposit:)
      @redemption = redemption
      @deposit = deposit
    end

    def call
      return Result.new(ok?: true, error: nil) if @redemption.status == "applied"

      ActiveRecord::Base.transaction do
        credit_user!(@redemption.redeemer_user, @redemption.redeemer_bonus_idr_snapshot, label: "Bonus dari kode #{@redemption.promo_code.code}")
        if @redemption.promo_code.referral? && @redemption.promo_code.inviter_user_id.present?
          credit_user!(
            @redemption.promo_code.inviter_user,
            @redemption.inviter_bonus_idr_snapshot,
            label: "Bonus referral #{@redemption.redeemer_user.email} → kode #{@redemption.promo_code.code}"
          )
        end
        @redemption.update!(
          status: "applied",
          applied_at: Time.current,
          triggered_by_deposit: @deposit
        )
        @redemption.promo_code.increment!(:redemptions_count)
      end

      Result.new(ok?: true, error: nil)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(ok?: false, error: e.message)
    end

    private

    def credit_user!(user, amount_idr, label:)
      return if amount_idr.to_i <= 0
      DepositTransaction.create!(
        user: user,
        amount: amount_idr,
        currency: "idr",
        payment_gateway: "manual",
        status: :completed,
        gateway_ref: label
      )
      user.increment!(:balance_idr, amount_idr)
    end
  end
end
