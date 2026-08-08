# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Logs", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:two) }
  let(:app_record) { app_records(:two) }

  it "redirects to login when not authenticated" do
    get "/dashboard/apps/#{app_record.id}/logs"
    expect(response).to have_http_status(:redirect)
  end

  it "shows logs page when authenticated (logs may be nil due to no SSH)" do
    sign_in user
    get "/dashboard/apps/#{app_record.id}/logs"
    expect(response).to have_http_status(:success)
  end
end
