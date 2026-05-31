# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Devices", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }

  before do
    sign_in user
    Rails.cache.clear
  end

  describe "GET show" do
    it "renders a blank form without a code" do
      get dashboard_device_path
      expect(response).to have_http_status(:success)
    end

    it "prefills user_code from the query param" do
      auth = DeviceAuthorization.start!
      get dashboard_device_path, params: { user_code: auth.user_code }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(auth.user_code)
    end

    it "requires authentication" do
      sign_out user
      get dashboard_device_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "POST authorize" do
    it "approves the request" do
      auth = DeviceAuthorization.start!
      post authorize_dashboard_device_path, params: { user_code: auth.user_code, decision: "approve" }
      expect(response).to have_http_status(:success)
      auth.reload
      expect(auth.status).to eq("approved")
      expect(auth.user_id).to eq(user.id)
    end

    it "denies the request" do
      auth = DeviceAuthorization.start!
      post authorize_dashboard_device_path, params: { user_code: auth.user_code, decision: "deny" }
      expect(response).to have_http_status(:success)
      expect(auth.reload.denied?).to be_truthy
    end

    it "rejects an unknown code" do
      post authorize_dashboard_device_path, params: { user_code: "BAAA-AAAA", decision: "approve" }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects an expired code" do
      auth = DeviceAuthorization.start!
      auth.update_column(:expires_at, 1.minute.ago)
      post authorize_dashboard_device_path, params: { user_code: auth.user_code, decision: "approve" }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
