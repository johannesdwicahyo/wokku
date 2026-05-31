# frozen_string_literal: true
require "rails_helper"

# D1 Sidebar IA cleanup — Task 5.
# Asserts the 2-item workspace nav, account section, and root redirect.
# The admin context is pending until Task 6 lands the admin_* route helpers.
RSpec.describe "Dashboard IA", type: :request do
  include Devise::Test::IntegrationHelpers

  context "as a regular user" do
    let(:user) { create(:user) }
    before { sign_in user }

    it "GET /dashboard redirects to /dashboard/apps" do
      get "/dashboard"
      expect(response).to redirect_to("/dashboard/apps")
    end

    it "GET /dashboard/addons redirects to /dashboard/apps" do
      get "/dashboard/addons"
      expect(response).to redirect_to("/dashboard/apps")
    end

    it "GET /dashboard/deploy redirects to /dashboard/apps/new" do
      get "/dashboard/deploy"
      expect(response).to redirect_to("/dashboard/apps/new")
    end

    it "sidebar renders apps + templates nav items but NOT dashboard/addons/deploy items" do
      get "/dashboard/apps"
      follow_redirect! while response.redirect?
      expect(response.body).to include("apps")
      expect(response.body).to include("templates")
      # Orphaned items should not appear as sidebar links
      expect(response.body).not_to include('href="/dashboard/addons"')
      expect(response.body).not_to include('href="/dashboard/deploys"')
    end
  end

  context "as an admin" do
    # The admin account is a singleton (admin@wokku.cloud) — use the fixture.
    let(:admin) { users(:admin) }
    before { sign_in admin }

    it "GET /admin is inaccessible to non-admin users" do
      sign_out admin
      sign_in users(:one)
      get "/admin"
      # Devise authenticate block with a lambda guard returns 404 for
      # authenticated-but-non-admin users (not a redirect).
      expect(response).not_to have_http_status(:success)
    end

    it "GET /admin renders the admin dashboard for an admin user" do
      get "/admin"
      expect(response).to have_http_status(:success)
    end

    it "GET /admin/servers renders servers index for an admin user" do
      get "/admin/servers"
      expect(response).to have_http_status(:success)
    end

    it "GET /admin/promo_codes renders promo codes index for an admin user" do
      get "/admin/promo_codes"
      expect(response).to have_http_status(:success)
    end

    it "GET /admin/users renders users index for an admin user" do
      get "/admin/users"
      expect(response).to have_http_status(:success)
    end
  end
end
