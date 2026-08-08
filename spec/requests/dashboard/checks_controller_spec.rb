# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Checks", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }
  let(:app_record) { app_records(:two) }

  describe "auth guard" do
    it "redirects to login when not authenticated on show" do
      get "/dashboard/apps/#{app_record.id}/checks"
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET show" do
    it "renders the checks page when authenticated" do
      sign_in user
      get "/dashboard/apps/#{app_record.id}/checks"
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH update" do
    it "redirects with the Swarm-managed alert — checks are platform-supervised" do
      sign_in user
      patch "/dashboard/apps/#{app_record.id}/checks",
            params: { checks_enabled: "1", check_path: "/health", checks_wait: "3", checks_timeout: "10", checks_attempts: "5" }
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/checks")
      expect(flash[:alert]).to match(/Swarm runtime/)
    end
  end
end
