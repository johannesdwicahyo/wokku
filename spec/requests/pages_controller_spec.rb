require "rails_helper"

RSpec.describe "PagesController", type: :request do
  include Devise::Test::IntegrationHelpers

  describe "landing page" do
    it "renders for an unauthenticated visitor" do
      get root_path
      expect(response).to have_http_status(:success)
    end

    it "redirects an authenticated user to the dashboard" do
      sign_in users(:one)
      get root_path
      expect(response).to redirect_to(dashboard_apps_path)
    end
  end

  describe "pricing page" do
    it "is accessible without login" do
      get pricing_path
      expect(response).to have_http_status(:success)
    end

    it "is accessible when signed in" do
      sign_in users(:one)
      get pricing_path
      expect(response).to have_http_status(:success)
    end

    it "renders tier data or fallback" do
      get pricing_path
      expect(response).to have_http_status(:success)
      expect(response.body).to match(/App Containers|Container Aplikasi/)
      expect(response.body).to match(/Databases|Database/)
    end
  end

  describe "deploy page" do
    it "is accessible without login" do
      get deploy_path
      expect(response).to have_http_status(:success)
    end
  end
end
