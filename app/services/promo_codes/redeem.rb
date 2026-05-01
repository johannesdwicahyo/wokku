module PromoCodes
  # Records a user's intent to redeem a code. The bonus does not land
  # immediately for channel_match or referral codes — those wait for a
  # qualifying deposit (handled by ApplyPendingForDeposit). manual_credit
  # codes apply on redemption since there's no deposit gate.
  class Redeem
    Result = Struct.new(:ok?, :promo_code, :error, keyword_init: true)

    def self.call(user:, code:)
      new(user: user, code: code).call
    end

    def initialize(user:, code:)
      @user = user
      @code = code.to_s.strip.upcase
    end

    def call
      return failure("Enter a code.") if @code.blank?

      promo = PromoCode.find_by("UPPER(code) = ?", @code)
      return failure("Code not found.")             unless promo
      return failure("This code has expired.")      unless promo.redeemable?
      return failure("Can't redeem your own referral code.") if promo.inviter_user_id == @user.id
      return failure("You've already used a code on this account.") if PromoRedemption.exists?(redeemer_user: @user)

      redemption = PromoRedemption.new(
        promo_code: promo,
        redeemer_user: @user,
        status: "pending",
        redeemer_bonus_idr_snapshot: promo.redeemer_bonus_idr,
        inviter_bonus_idr_snapshot: promo.inviter_bonus_idr
      )

      ActiveRecord::Base.transaction do
        redemption.save!
        if promo.instant_grant?
          ApplyBonus.call(redemption: redemption, deposit: nil)
        end
      end

      Result.new(ok?: true, promo_code: promo, error: nil)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.message)
    end

    private

    def failure(msg)
      Result.new(ok?: false, promo_code: nil, error: msg)
    end
  end
end
