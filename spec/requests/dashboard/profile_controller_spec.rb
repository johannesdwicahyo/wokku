# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Profile", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }

  it "redirects to login when not authenticated" do
    get "/dashboard/profile"
    expect(response).to have_http_status(:redirect)
  end

  it "shows profile when authenticated" do
    sign_in user
    get "/dashboard/profile"
    expect(response).to have_http_status(:success)
  end

  it "clears email_provider_verified when the email is edited" do
    user.update_columns(email_provider_verified: true)
    sign_in user
    patch "/dashboard/profile", params: { user: { email: "edited-#{SecureRandom.hex(3)}@example.com" } }
    expect(user.reload.email_provider_verified).to be(false)
  end
end
