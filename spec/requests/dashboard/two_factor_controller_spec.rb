# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::TwoFactor", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }

  it "redirects to login when not authenticated on show" do
    get "/dashboard/two_factor"
    expect(response).to have_http_status(:redirect)
  end

  it "shows two factor setup page when authenticated" do
    sign_in user
    get "/dashboard/two_factor"
    expect(response).to have_http_status(:success)
  end

  it "redirects to login when not authenticated on enable" do
    post "/dashboard/two_factor/enable", params: { otp_code: "123456" }
    expect(response).to have_http_status(:redirect)
  end

  it "enable with invalid OTP re-renders show" do
    sign_in user
    post "/dashboard/two_factor/enable", params: { otp_code: "000000" }
    expect(response).to have_http_status(:success)
  end

  it "redirects to login when not authenticated on disable" do
    delete "/dashboard/two_factor/disable", params: { otp_code: "123456" }
    expect(response).to have_http_status(:redirect)
  end

  it "disable with invalid OTP redirects back to two_factor" do
    sign_in user
    delete "/dashboard/two_factor/disable", params: { otp_code: "000000" }
    expect(response).to redirect_to("/dashboard/two_factor")
  end
end
