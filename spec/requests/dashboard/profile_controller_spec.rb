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
end
