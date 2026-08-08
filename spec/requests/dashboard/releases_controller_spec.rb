# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Releases", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:two) }
  let(:app_record) { app_records(:two) }
  let(:release)    { releases(:two) }

  before do
    # Prevent DeployJob/RollbackDeployJob from actually enqueuing Sidekiq work
    allow(DeployJob).to receive(:perform_later).and_return(nil)
    allow(RollbackDeployJob).to receive(:perform_later).and_return(nil)
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

  describe "POST rollback — real rollback (Track A Phase 4a Task 4, dashboard rider)" do
    it "rolls back to a release with a still-live rollback image, enqueues RollbackDeployJob, creates records, and redirects" do
      sign_in user
      tag = "#{Hosts::Registry::HOST}/wokku-rollback/#{app_record.name}:11111111-1111-1111-1111-111111111111"
      rel = app_record.releases.create!(description: "historical")
      app_record.deploys.create!(release: rel, status: :succeeded, image_ref: tag)
      allow_any_instance_of(Hosts::Registry).to receive(:tags)
        .with("wokku-rollback/#{app_record.name}")
        .and_return([ "11111111-1111-1111-1111-111111111111" ])

      expect {
        post "/dashboard/apps/#{app_record.id}/releases/#{rel.id}/rollback"
      }.to change { app_record.releases.count }.by(1)
        .and change { app_record.deploys.count }.by(1)
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/releases")
      expect(flash[:notice]).to match("Rolling back")

      new_deploy = app_record.deploys.order(:created_at).last
      expect(new_deploy.image_ref).to eq(tag)
      expect(RollbackDeployJob).to have_received(:perform_later).with(app_id: app_record.id, deploy_id: new_deploy.id)
    end

    it "shows a flash alert with the hint and creates no records when no artifact remains for the release" do
      sign_in user
      rel = release # fixture: legacy sha-only deploy, no image_ref/archive_key

      expect {
        post "/dashboard/apps/#{app_record.id}/releases/#{rel.id}/rollback"
      }.not_to change { app_record.deploys.count }
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/releases")
      expect(flash[:alert]).to include("legacy deploy")
      expect(RollbackDeployJob).not_to have_received(:perform_later)
    end
  end
end
