# frozen_string_literal: true

require "rails_helper"

# Moved to Admin::ServersController — paths are now /admin/servers/*.
RSpec.describe "Admin::Servers", type: :request do
  include Devise::Test::IntegrationHelpers

  it "redirects to login when not authenticated" do
    get "/admin/servers"
    expect(response).to have_http_status(:redirect)
  end

  it "shows servers index to platform admins" do
    admin = users(:admin)
    admin.update!(otp_required_for_login: true)
    sign_in admin
    get "/admin/servers"
    expect(response).to have_http_status(:success)
  end

  it "non-admin cannot access /admin/servers (Devise authenticate block returns 404)" do
    sign_in users(:one)
    get "/admin/servers"
    expect(response).to have_http_status(:not_found)
  end
end
