# frozen_string_literal: true

require "rails_helper"

# U1: the rail's Databases item points at /dashboard/addons. The old
# `get "/addons" => redirect(apps)` shadow (declared before the resources
# block) must be gone so the databases index actually serves.
RSpec.describe "GET /dashboard/addons", type: :request do
  include Devise::Test::IntegrationHelpers

  it "renders the databases list instead of redirecting to apps" do
    sign_in users(:one)
    get "/dashboard/addons"
    expect(response).to have_http_status(:ok)
  end
end
