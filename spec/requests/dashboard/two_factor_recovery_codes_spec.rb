# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard 2FA recovery codes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user, :with_personal_team) }

  before { sign_in user }

  it "shows 10 recovery codes once after enabling" do
    get "/dashboard/two_factor"
    post "/dashboard/two_factor/enable", params: { otp_code: user.reload.current_otp }
    expect(response).to have_http_status(:ok)
    codes = response.body.scan(/\b\h{20}\b/).uniq
    expect(codes.size).to eq(10)
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("auth.two_factor.codes_save_now")))
    expect(user.reload.otp_backup_codes.size).to eq(10)

    get "/dashboard/two_factor"
    expect(response.body.scan(/\b\h{20}\b/)).to be_empty
    expect(response.body).to include(I18n.t("auth.two_factor.codes_remaining", count: 10))
  end

  context "with 2FA enabled" do
    before do
      user.update!(otp_secret: User.generate_otp_secret, otp_required_for_login: true)
      user.generate_otp_backup_codes!
      user.save!
    end

    it "regenerates only with a valid code" do
      old = user.otp_backup_codes
      post "/dashboard/two_factor/regenerate_codes", params: { otp_code: "000000" }
      expect(response).to redirect_to("/dashboard/two_factor")
      expect(user.reload.otp_backup_codes).to eq(old)

      post "/dashboard/two_factor/regenerate_codes", params: { otp_code: user.current_otp }
      expect(response).to have_http_status(:ok)
      expect(response.body.scan(/\b\h{20}\b/).uniq.size).to eq(10)
      expect(user.reload.otp_backup_codes).not_to eq(old)
    end

    it "disables with a recovery code and clears the codes" do
      code = user.generate_otp_backup_codes!.first
      user.save!
      delete "/dashboard/two_factor/disable", params: { otp_code: code }
      user.reload
      expect(user.two_factor_enabled?).to be false
      expect(user.otp_backup_codes).to be_blank
    end
  end
end
