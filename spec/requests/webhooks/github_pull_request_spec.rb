# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Webhooks::Github pull_request", type: :request do
  let(:team) { create(:team) }
  let!(:parent) do
    create(:app_record, team: team, github_repo_full_name: "octo/repo", preview_enabled: true)
  end
  let(:payload) { File.read(Rails.root.join("spec/fixtures/webhooks/github/pull_request_opened.json")) }

  before do
    allow(GithubApp).to receive(:verify_webhook_signature).and_return(true)
    create(:team_membership, team: team, user: create(:user, github_installation_id: 42))
  end

  it "enqueues Preview::DeployJob via EventDispatcher" do
    expect {
      post "/webhooks/github",
           params: payload,
           headers: { "Content-Type" => "application/json", "X-GitHub-Event" => "pull_request", "X-Hub-Signature-256" => "sha256=any" }
    }.to have_enqueued_job(Preview::DeployJob)
  end

  it "skips a parent whose team doesn't own the PR's installation" do
    TeamMembership.where(team: team).destroy_all
    expect {
      post "/webhooks/github",
           params: payload,
           headers: { "Content-Type" => "application/json", "X-GitHub-Event" => "pull_request", "X-Hub-Signature-256" => "sha256=any" }
    }.not_to have_enqueued_job(Preview::DeployJob)
  end

  it "no-ops when no parent has the repo connected" do
    parent.update!(github_repo_full_name: "other/repo")
    expect {
      post "/webhooks/github",
           params: payload,
           headers: { "Content-Type" => "application/json", "X-GitHub-Event" => "pull_request", "X-Hub-Signature-256" => "sha256=any" }
    }.not_to have_enqueued_job(Preview::DeployJob)
  end

  it "rejects when signature verification fails" do
    allow(GithubApp).to receive(:verify_webhook_signature).and_return(false)
    post "/webhooks/github",
         params: payload,
         headers: { "Content-Type" => "application/json", "X-GitHub-Event" => "pull_request", "X-Hub-Signature-256" => "sha256=bad" }
    expect(response.status).to be_in([ 401, 403 ])
  end
end
