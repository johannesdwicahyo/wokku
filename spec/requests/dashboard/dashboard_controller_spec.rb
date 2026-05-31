# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Dashboard", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }

  describe "GET /dashboard/" do
    it "redirects when not authenticated" do
      get "/dashboard/"
      expect(response).to have_http_status(:redirect)
    end

    it "redirects to /dashboard/apps when authenticated" do
      sign_in user
      get "/dashboard/"
      # /dashboard/ is a permanent redirect to /dashboard/apps for everyone.
      expect(response).to redirect_to("/dashboard/apps")
    end

    it "lets a member (role 0) access the dashboard (via the redirect)" do
      sign_in users(:one)
      get "/dashboard/"
      expect(response).to redirect_to("/dashboard/apps")
    end
  end
end
