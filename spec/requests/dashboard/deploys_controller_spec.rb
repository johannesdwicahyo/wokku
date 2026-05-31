# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Deploys", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }
  let(:app_record) { app_records(:two) }
  let(:deploy) { deploys(:two) }

  it "redirects to login when not authenticated" do
    get "/dashboard/apps/#{app_record.id}/deploys/#{deploy.id}"
    expect(response).to have_http_status(:redirect)
  end

  it "shows the deploy when authenticated" do
    sign_in user
    get "/dashboard/apps/#{app_record.id}/deploys/#{deploy.id}"
    expect(response).to have_http_status(:success)
  end
end
