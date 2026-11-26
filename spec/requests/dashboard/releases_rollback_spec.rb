# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Releases rollback", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:team) do
    t = create(:team, owner: user)
    create(:team_membership, team: t, user: user, role: :admin)
    t
  end
  let(:server) { create(:server, team: team) }
  let(:target_app) { create(:app_record, team: team, server: server, creator: user) }

  # Build a clean release/deploy history on a fresh app — avoids version
  # collisions with fixture data and keeps the test self-contained.
  let!(:r1) { Release.create!(app_record: target_app, description: "Initial deploy") } # v1
  let!(:d1) { Deploy.create!(app_record: target_app, release: r1, status: :succeeded, commit_sha: "abc1234aaa") }
  let!(:r2) { Release.create!(app_record: target_app, description: "Feature X") }      # v2
  let!(:d2) { Deploy.create!(app_record: target_app, release: r2, status: :succeeded, commit_sha: "def5678bbb") }
  let!(:r3) { Release.create!(app_record: target_app, description: "Bad release") }    # v3
  let!(:d3) { Deploy.create!(app_record: target_app, release: r3, status: :failed, commit_sha: "fail9999cc") }

  before do
    r1.update!(deploy_id: d1.id)
    r2.update!(deploy_id: d2.id)
    r3.update!(deploy_id: d3.id)
    sign_in user
  end

  describe "GET /dashboard/apps/:app_id/releases" do
    it "renders successfully and identifies the current release as the latest succeeded" do
      get "/dashboard/apps/#{target_app.id}/releases"
      expect(response).to have_http_status(:ok)
      # r2 is the newest succeeded — should be marked current
      # (brutalist redesign P3c lowercased the badge copy)
      expect(response.body).to include("current")
    end

    it "shows a Rollback button for older succeeded releases" do
      get "/dashboard/apps/#{target_app.id}/releases"
      # The rollback form posts to /releases/:id/rollback for r1 (older succeeded)
      expect(response.body).to include("/releases/#{r1.id}/rollback")
      expect(response.body).to include("rollback")
    end

    it "hides Deploy now and Rollback from a viewer" do
      viewer = create(:user)
      create(:team_membership, team: team, user: viewer, role: :viewer)
      sign_in viewer
      get "/dashboard/apps/#{target_app.id}/releases"
      expect(response.body).not_to include("Deploy now")
      expect(response.body).not_to include("/releases/#{r1.id}/rollback")
    end

    it "shows Deploy now and Roll back to a member" do
      get "/dashboard/apps/#{target_app.id}/releases"
      expect(response.body).to include("Deploy now")
      expect(response.body).to include("Roll back")
    end

    it "does NOT show a Rollback button for the current (newest succeeded) release" do
      get "/dashboard/apps/#{target_app.id}/releases"
      expect(response.body).not_to include("/releases/#{r2.id}/rollback")
    end

    it "does NOT show a Rollback button for failed releases" do
      get "/dashboard/apps/#{target_app.id}/releases"
      expect(response.body).not_to include("/releases/#{r3.id}/rollback")
    end
  end

  describe "POST /dashboard/apps/:app_id/releases/:id/rollback" do
    # Real rollback (Track A Phase 4a Task 4, dashboard rider): the target
    # deploy needs a live artifact (image tag still on the host, or an
    # archive still in storage) — d1 only carries a commit_sha by default,
    # which resolves to "no artifact" (see the rejection spec below). Give
    # it an image_ref + a live host tag for the success-path specs.
    let(:tag) { "#{Hosts::Registry::HOST}/wokku-rollback/#{target_app.name}:11111111-1111-1111-1111-111111111111" }

    before do
      d1.update!(image_ref: tag)
      allow_any_instance_of(Hosts::Registry).to receive(:tags)
        .with("wokku-rollback/#{target_app.name}")
        .and_return([ "11111111-1111-1111-1111-111111111111" ])
    end

    it "creates a new Release + Deploy pointing at the target's rollback image" do
      expect {
        post "/dashboard/apps/#{target_app.id}/releases/#{r1.id}/rollback"
      }.to change { target_app.releases.count }.by(1)
        .and change { target_app.deploys.count }.by(1)

      new_release = target_app.releases.order(:version).last
      expect(new_release.description).to include("Rollback to v#{r1.version}")
      # The controller creates a Deploy pointing at the new release but
      # doesn't back-fill release.deploy_id, so look it up directly.
      new_deploy = target_app.deploys.where(release_id: new_release.id).first
      expect(new_deploy.image_ref).to eq(tag)
      expect(new_deploy.status).to eq("pending")
    end

    it "enqueues RollbackDeployJob for the new deploy" do
      expect {
        post "/dashboard/apps/#{target_app.id}/releases/#{r1.id}/rollback"
      }.to have_enqueued_job(RollbackDeployJob)
    end

    it "redirects with a success notice" do
      post "/dashboard/apps/#{target_app.id}/releases/#{r1.id}/rollback"
      expect(response).to redirect_to("/dashboard/apps/#{target_app.id}/releases")
      follow_redirect!
      expect(response.body).to include("Rolling back to v#{r1.version}")
    end

    it "shows a flash alert with the hint and creates no records when the target deploy has no recorded artifact" do
      d1.update!(image_ref: nil) # back to the default: commit_sha only, no artifact
      expect {
        post "/dashboard/apps/#{target_app.id}/releases/#{r1.id}/rollback"
      }.not_to change { target_app.releases.count }
      follow_redirect!
      expect(response.body).to include("legacy deploy")
    end

    it "rejects when not authenticated" do
      sign_out user
      post "/dashboard/apps/#{target_app.id}/releases/#{r1.id}/rollback"
      expect(response.status).to be_in([ 302, 401 ])
    end
  end
end
