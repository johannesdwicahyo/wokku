# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Releases", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:two) }
  let(:app_record) { app_records(:two) }
  let(:release)    { releases(:two) }

  before do
    # Prevent DeployJob from actually enqueuing Sidekiq work
    allow(DeployJob).to receive(:perform_later).and_return(nil)
  end

  it "redirects to login when not authenticated on index" do
    get "/dashboard/apps/#{app_record.id}/releases"
    expect(response).to have_http_status(:redirect)
  end

  it "shows releases index when authenticated" do
    sign_in user
    get "/dashboard/apps/#{app_record.id}/releases"
    expect(response).to have_http_status(:success)
  end

  it "triggers a deploy, creates release + deploy records, and redirects" do
    sign_in user
    expect {
      post "/dashboard/apps/#{app_record.id}/releases/deploy"
    }.to change { app_record.releases.count }.by(1)
      .and change { app_record.deploys.count }.by(1)
    expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/releases")
    expect(flash[:notice]).to match("Deploy triggered")
  end

  it "rolls back to a specific release, creates records, and redirects" do
    sign_in user
    rel = release
    expect {
      post "/dashboard/apps/#{app_record.id}/releases/#{rel.id}/rollback"
    }.to change { app_record.releases.count }.by(1)
      .and change { app_record.deploys.count }.by(1)
    expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/releases")
    expect(flash[:notice]).to match("Rolling back")
  end
end
