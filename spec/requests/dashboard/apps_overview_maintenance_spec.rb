# frozen_string_literal: true

require "rails_helper"

# Task 4 — Overview maintenance instant-render
#
# fetch_maintenance_enabled performed a blocking SSH call (60s cache) in #show
# purely to set @maintenance_enabled, which was never consumed by any view or
# component. Path A: the dead call is deleted entirely from #show.
RSpec.describe "Dashboard::Apps overview maintenance instant-render", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }
  let(:app_record) { app_records(:two) }

  before do
    stub_request(:any, %r{\Ahttps://api\.cloudflare\.com/})
      .to_return(status: 200, body: { success: true, result: [] }.to_json,
                 headers: { "Content-Type" => "application/json" })
    sign_in user
  end

  it "returns 200 for the app overview (GET show)" do
    get "/dashboard/apps/#{app_record.id}"
    expect(response).to have_http_status(:success)
  end

  it "no longer defines the blocking maintenance SSH fetch (removed from #show)" do
    expect(Dashboard::AppsController.private_instance_methods)
      .not_to include(:fetch_maintenance_enabled)
    get "/dashboard/apps/#{app_record.id}"
    expect(response).to have_http_status(:success)
  end
end
