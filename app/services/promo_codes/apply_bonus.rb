module PromoCodes
  # Pays out a redemption by creating an InvoiceCredit for each side
  # (redeemer + inviter for referrals). Replaces the deposit-era pattern
  # of bumping `User#balance_idr` — that column is no-op under Phase 4
  # invoice billing.
  #
  # Trigger: the iPaymu webhook calls us when the redeemer's first
  # non-trial invoice is paid. We use the paid invoice as the activation
  # signal (equivalent to the old min_deposit_idr gate — only pay out
  # the referral bonus once the redeemer is a genuine paid subscriber).
  #
  # Idempotent at the row level via PromoRedemption#status: once a
  # redemption is "applied" it won't be applied again. Safe to retry
  # from the webhook.
  class ApplyBonus
    Result = Struct.new(:ok?, :error, keyword_init: true)

    def self.call(redemption:, paid_invoice:)
      new(redemption: redemption, paid_invoice: paid_invoice).call
    end

    def initialize(redemption:, paid_invoice:)
      @redemption = redemption
      @paid_invoice = paid_invoice
    end

    def call
      return Result.new(ok?: true, error: nil) if @redemption.status == "applied"

      ActiveRecord::Base.transaction do
        credit_user!(
          @redemption.redeemer_user,
          @redemption.redeemer_bonus_idr_snapshot,
          source_ref: "PromoRedemption:#{@redemption.id}:redeemer"
        )
        if @redemption.promo_code.referral? && @redemption.promo_code.inviter_user_id.present?
          credit_user!(
            @redemption.promo_code.inviter_user,
            @redemption.inviter_bonus_idr_snapshot,
            source_ref: "PromoRedemption:#{@redemption.id}:inviter"
          )
        end
        @redemption.update!(status: "applied", applied_at: Time.current)
        @redemption.promo_code.increment!(:redemptions_count)
      end

      Result.new(ok?: true, error: nil)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(ok?: false, error: e.message)
    end

    private

    def credit_user!(user, amount_idr, source_ref:)
      return if amount_idr.to_i <= 0
      InvoiceCredit.create!(
        user: user,
        amount_idr: amount_idr.to_i,
        source: "promo:#{@redemption.promo_code.kind}",
        source_ref: source_ref
      )
    end
  end
end
