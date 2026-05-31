require "rails_helper"

RSpec.describe PromoCodes::ApplyBonus do
  let(:inviter) { users(:one) }
  let(:redeemer) do
    User.create!(email: "redeemer-#{SecureRandom.hex(4)}@example.com",
                 password: "supersecret123",
                 password_confirmation: "supersecret123")
  end

  let(:promo_code) do
    PromoCode.create!(
      code: "REF-TEST#{SecureRandom.hex(2).upcase}",
      kind: "referral",
      redeemer_bonus_idr: 10_000,
      inviter_bonus_idr: 10_000,
      inviter_user: inviter
    )
  end

  let(:redemption) do
    PromoRedemption.create!(
      promo_code: promo_code,
      redeemer_user: redeemer,
      status: "pending",
      redeemer_bonus_idr_snapshot: 10_000,
      inviter_bonus_idr_snapshot: 10_000
    )
  end

  let(:paid_invoice) do
    Invoice.create!(user: redeemer, amount_idr: 80_000, amount_cents: 0, status: :paid,
                    paid_at: Time.current, kind: :renewal,
                    period_start: Date.current, period_end: Date.current.next_month,
                    period_label: "Test",
                    reference_id: "INV-#{redeemer.id}-#{SecureRandom.hex(4)}")
  end

  it "creates InvoiceCredit for both redeemer and inviter" do
    expect {
      described_class.call(redemption: redemption, paid_invoice: paid_invoice)
    }.to change { InvoiceCredit.count }.by(2)

    expect(InvoiceCredit.for_user(redeemer).sum(:amount_idr)).to eq(10_000)
    expect(InvoiceCredit.for_user(inviter).sum(:amount_idr)).to eq(10_000)
  end

  it "marks the redemption applied" do
    described_class.call(redemption: redemption, paid_invoice: paid_invoice)
    expect(redemption.reload.status).to eq("applied")
    expect(redemption.applied_at).not_to be_nil
  end

  it "is idempotent — calling twice does not create duplicate credits" do
    described_class.call(redemption: redemption, paid_invoice: paid_invoice)
    expect {
      described_class.call(redemption: redemption, paid_invoice: paid_invoice)
    }.not_to change { InvoiceCredit.count }
  end

  # (Previously: "does NOT touch balance_idr" — that column was dropped
  # entirely in 1.8, so the test is no longer meaningful.)

  it "skips inviter credit for non-referral promo codes" do
    promo_code.update!(kind: "manual_credit", inviter_user_id: nil)
    expect {
      described_class.call(redemption: redemption, paid_invoice: paid_invoice)
    }.to change { InvoiceCredit.count }.by(1) # only redeemer
  end
end
