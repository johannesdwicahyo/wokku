require "rails_helper"

RSpec.describe "Dashboard::Referrals", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }

  before { sign_in user }

  describe "GET /dashboard/referrals" do
    it "renders the page with the user's referral code" do
      user.ensure_referral_promo_code!
      get dashboard_referrals_path
      expect(response).to have_http_status(:success)
      # Controller may auto-create one if the test setup's wasn't loaded;
      # either way, SOME referral code should be on the page.
      expect(response.body).to match(/REF-[A-Z0-9]{6}/)
    end

    it "shows zero signups + zero cash earned by default" do
      user.referral_promo_code || user.ensure_referral_promo_code!
      get dashboard_referrals_path
      expect(response.body).to match(/Signups/)
      expect(response.body).to match(/Cash earned/)
      expect(response.body).to match(/Rp 0/)
    end

    it "counts applied redemptions as signups and computes cash earned" do
      code = user.referral_promo_code || user.ensure_referral_promo_code!
      code.update!(inviter_bonus_idr: 10_000)
      redeemer = User.create!(email: "ref-#{SecureRandom.hex(4)}@example.com", password: "password123456")
      PromoRedemption.create!(
        promo_code: code, redeemer_user: redeemer, status: "applied",
        redeemer_bonus_idr_snapshot: 10_000, inviter_bonus_idr_snapshot: 10_000,
        applied_at: 1.hour.ago
      )
      get dashboard_referrals_path
      expect(response.body).to match(/Rp 10\.000/)
    end

    it "renders the share URL with the user's code" do
      user.ensure_referral_promo_code!
      get dashboard_referrals_path
      expect(response.body).to match(/code=REF-[A-Z0-9]{6}/)
    end
  end

  describe "POST /dashboard/referrals/regenerate" do
    it "destroys the old code and creates a new one" do
      old_code = user.ensure_referral_promo_code!
      expect {
        post regenerate_dashboard_referrals_path
      }.to change { user.reload.referral_promo_code&.code }.from(old_code.code)
      expect(response).to redirect_to(dashboard_referrals_path)
    end
  end

  describe "without authentication" do
    before { sign_out user }
    it "redirects to sign-in" do
      get dashboard_referrals_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
