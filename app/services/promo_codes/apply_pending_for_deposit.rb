module PromoCodes
  # Called from DepositTransaction#complete! after balance settles. Walks
  # any pending redemptions on this user and applies the ones whose
  # min_deposit threshold this deposit meets. Today we expect at most
  # one pending row per user (Redeem enforces single redemption), but the
  # scope-and-walk pattern is cheap and defensive.
  class ApplyPendingForDeposit
    def self.call(deposit:)
      return unless deposit.completed? && deposit.currency == "idr" && deposit.amount.to_i > 0
      PromoRedemption.pending
                     .where(redeemer_user_id: deposit.user_id)
                     .includes(:promo_code)
                     .find_each do |redemption|
        next unless deposit.amount.to_i >= redemption.promo_code.min_deposit_idr.to_i
        ApplyBonus.call(redemption: redemption, deposit: deposit)
      end
    end
  end
end
