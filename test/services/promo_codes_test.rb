require "test_helper"

class PromoCodesTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(currency: "idr", balance_idr: 0)
    @other = users(:two)
    @other.update!(currency: "idr", balance_idr: 0)
  end

  # ── Phase 1 — manual credit
  test "manual_credit code lands instantly on redemption" do
    promo = PromoCode.create!(code: "WELCOME50", kind: "manual_credit", redeemer_bonus_idr: 50_000, min_deposit_idr: 0)
    result = PromoCodes::Redeem.call(user: @user, code: "welcome50")
    assert result.ok?, result.error
    assert_equal 50_000, @user.reload.balance_idr
    assert_equal "applied", PromoRedemption.last.status
    assert_equal 1, promo.reload.redemptions_count
  end

  # ── Phase 2 — channel match
  test "channel_match code is pending until first qualifying deposit" do
    PromoCode.create!(code: "LARAVELID", kind: "channel_match", redeemer_bonus_idr: 25_000, min_deposit_idr: 25_000)
    PromoCodes::Redeem.call(user: @user, code: "LARAVELID")
    assert_equal 0, @user.reload.balance_idr
    assert_equal "pending", PromoRedemption.last.status

    deposit = DepositTransaction.create!(user: @user, amount: 25_000, currency: "idr", payment_gateway: "ipaymu", status: :pending)
    deposit.complete!

    assert_equal 25_000 + 25_000, @user.reload.balance_idr
    assert_equal "applied", PromoRedemption.last.reload.status
  end

  test "channel_match: deposit below threshold does NOT apply bonus" do
    PromoCode.create!(code: "LARAVELID", kind: "channel_match", redeemer_bonus_idr: 25_000, min_deposit_idr: 25_000)
    PromoCodes::Redeem.call(user: @user, code: "LARAVELID")

    deposit = DepositTransaction.create!(user: @user, amount: 10_000, currency: "idr", payment_gateway: "ipaymu", status: :pending)
    deposit.complete!

    assert_equal 10_000, @user.reload.balance_idr
    assert_equal "pending", PromoRedemption.last.status
  end

  # ── Phase 3 — referral
  test "referral code pays both sides on referee's qualifying first deposit" do
    inviter_code = @user.ensure_referral_promo_code!
    PromoCodes::Redeem.call(user: @other, code: inviter_code.code)

    deposit = DepositTransaction.create!(user: @other, amount: 25_000, currency: "idr", payment_gateway: "ipaymu", status: :pending)
    deposit.complete!

    assert_equal 25_000 + 10_000, @other.reload.balance_idr, "referee gets deposit + 10k bonus"
    assert_equal 10_000,           @user.reload.balance_idr,  "inviter gets 10k bonus"
  end

  test "user cannot redeem their own referral code" do
    code = @user.ensure_referral_promo_code!
    result = PromoCodes::Redeem.call(user: @user, code: code.code)
    refute result.ok?
    assert_match(/own referral/i, result.error)
  end

  # ── Abuse / edge cases
  test "user can only redeem one code per account" do
    PromoCode.create!(code: "FIRST", kind: "channel_match", redeemer_bonus_idr: 25_000, min_deposit_idr: 25_000)
    PromoCode.create!(code: "SECOND", kind: "channel_match", redeemer_bonus_idr: 25_000, min_deposit_idr: 25_000)
    assert PromoCodes::Redeem.call(user: @user, code: "FIRST").ok?
    refute PromoCodes::Redeem.call(user: @user, code: "SECOND").ok?
  end

  test "expired code rejected" do
    PromoCode.create!(code: "OLD", kind: "manual_credit", redeemer_bonus_idr: 50_000, min_deposit_idr: 0, expires_at: 1.minute.ago)
    refute PromoCodes::Redeem.call(user: @user, code: "OLD").ok?
  end

  test "max_redemptions cap enforced" do
    PromoCode.create!(code: "LIMITED", kind: "manual_credit", redeemer_bonus_idr: 50_000, min_deposit_idr: 0, max_redemptions: 1)
    assert PromoCodes::Redeem.call(user: @user, code: "LIMITED").ok?
    refute PromoCodes::Redeem.call(user: @other, code: "LIMITED").ok?
  end

  test "manual deposits do NOT trigger pending redemptions (so admin top-ups stay clean)" do
    PromoCode.create!(code: "LARAVELID", kind: "channel_match", redeemer_bonus_idr: 25_000, min_deposit_idr: 25_000)
    PromoCodes::Redeem.call(user: @user, code: "LARAVELID")

    deposit = DepositTransaction.create!(user: @user, amount: 25_000, currency: "idr", payment_gateway: "manual", status: :pending)
    deposit.complete!

    assert_equal 25_000, @user.reload.balance_idr, "manual deposit credits balance but skips promo path"
    assert_equal "pending", PromoRedemption.last.status
  end

  test "after_create on User generates a referral code" do
    u = User.create!(email: "newby@example.com", password: "password123456", currency: "idr")
    assert u.reload.referral_promo_code.present?
    assert_match(/\AREF-/, u.referral_promo_code.code)
  end
end
