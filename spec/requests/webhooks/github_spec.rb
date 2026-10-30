# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Webhooks::GithubController", type: :request do
  def signed_post(payload, event: "push")
    allow(GithubApp).to receive(:verify_webhook_signature).and_return(true)
    post "/webhooks/github",
         params: payload,
         headers: {
           "Content-Type" => "application/json",
           "X-GitHub-Event" => event,
           "X-Hub-Signature-256" => "sha256=valid"
         }
  end

  # ---------------------------------------------------------------------------
  # Signature verification
  # ---------------------------------------------------------------------------

  it "rejects unsigned webhook" do
    post "/webhooks/github", params: "{}", headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects webhook with wrong signature" do
    allow(GithubApp).to receive(:verify_webhook_signature).and_return(false)
    post "/webhooks/github",
         params: '{"zen":"test"}',
         headers: {
           "Content-Type" => "application/json",
           "X-GitHub-Event" => "ping",
           "X-Hub-Signature-256" => "sha256=invalidsignature"
         }
    expect(response).to have_http_status(:unauthorized)
  end

  it "accepts ping event with valid signature" do
    signed_post('{"zen":"test"}', event: "ping")
    expect(response).to have_http_status(:ok)
  end

  it "accepts unknown event with valid signature" do
    signed_post('{"action":"unknown"}', event: "create")
    expect(response).to have_http_status(:ok)
  end

  # ---------------------------------------------------------------------------
  # Push events
  # ---------------------------------------------------------------------------

  context "push event" do
    let!(:deploy_app) { create(:app_record, github_repo_full_name: "owner/matching-repo", deploy_branch: "main") }

    it "enqueues GithubDeployJob for matching app" do
      payload = { ref: "refs/heads/main",
                  repository: { full_name: "owner/matching-repo" },
                  head_commit: { id: "abc123def456", message: "Fix bug" } }.to_json
      expect {
        signed_post(payload, event: "push")
      }.to have_enqueued_job(GithubDeployJob)
      expect(response).to have_http_status(:ok)
    end

    it "creates Deploy and Release records" do
      payload = { ref: "refs/heads/main",
                  repository: { full_name: "owner/matching-repo" },
                  head_commit: { id: "deadbeef1234", message: "feat: new feature" } }.to_json
      expect {
        signed_post(payload, event: "push")
      }.to change(Deploy, :count).by(1).and change(Release, :count).by(1)
    end

    it "skips an app whose deploys are locked" do
      deploy_app.update!(deploy_locked_at: Time.current)
      payload = { ref: "refs/heads/main",
                  repository: { full_name: "owner/matching-repo" },
                  head_commit: { id: "deadbeef1234", message: "x" } }.to_json
      expect { signed_post(payload, event: "push") }.not_to change(Deploy, :count)
      expect(response).to have_http_status(:ok)
    end

    it "does not trigger for non-matching branch" do
      payload = { ref: "refs/heads/feature-branch",
                  repository: { full_name: "owner/matching-repo" },
                  head_commit: { id: "abc123", message: "WIP" } }.to_json
      expect {
        signed_post(payload, event: "push")
      }.not_to have_enqueued_job(GithubDeployJob)
      expect(response).to have_http_status(:ok)
    end

    it "returns ok with missing repo without enqueueing" do
      payload = { ref: "refs/heads/main", repository: {},
                  head_commit: { id: "abc123", message: "test" } }.to_json
      expect {
        signed_post(payload, event: "push")
      }.not_to have_enqueued_job(GithubDeployJob)
      expect(response).to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------------
  # pull_request events — routed through Preview::EventDispatcher
  # ---------------------------------------------------------------------------

  context "pull_request event" do
    let(:team) { create(:team) }
    let!(:parent) do
      create(:app_record, team: team, github_repo_full_name: "owner/pr-test-repo",
             git_provider: "github", git_repo_full_name: "owner/pr-test-repo",
             preview_enabled: true)
    end

    it "enqueues Preview::DeployJob for opened action" do
      payload = { action: "opened", number: 42,
                  pull_request: { number: 42, title: "My Feature",
                                  head: { ref: "feature-branch", sha: "abc123" },
                                  user: { login: "dev" }, merged: false },
                  repository: { full_name: "owner/pr-test-repo" },
                  installation: { id: 1 } }.to_json
      expect {
        signed_post(payload, event: "pull_request")
      }.to have_enqueued_job(Preview::DeployJob)
      expect(response).to have_http_status(:ok)
    end

    it "enqueues Preview::DeployJob for synchronize action" do
      payload = { action: "synchronize", number: 10,
                  pull_request: { number: 10, title: "Sync PR",
                                  head: { ref: "feature", sha: "sha999" },
                                  user: { login: "dev" }, merged: false },
                  repository: { full_name: "owner/pr-test-repo" },
                  installation: { id: 1 } }.to_json
      expect {
        signed_post(payload, event: "pull_request")
      }.to have_enqueued_job(Preview::DeployJob)
    end

    it "enqueues Preview::CleanupJob for closed action when preview exists" do
      preview = create(:app_record, :preview, parent_app: parent, pr_number: 7)
      payload = { action: "closed", number: 7,
                  pull_request: { number: 7, title: "Closed PR",
                                  head: { ref: "feature", sha: "sha000" },
                                  user: { login: "dev" }, merged: false },
                  repository: { full_name: "owner/pr-test-repo" },
                  installation: { id: 1 } }.to_json
      expect {
        signed_post(payload, event: "pull_request")
      }.to have_enqueued_job(Preview::CleanupJob)
    end

    it "no-ops when no parent has the repo connected" do
      payload = { action: "opened", number: 99,
                  pull_request: { number: 99, title: "Orphan PR",
                                  head: { ref: "feature", sha: "sha" },
                                  user: { login: "dev" }, merged: false },
                  repository: { full_name: "nobody/nonexistent-repo" },
                  installation: { id: 1 } }.to_json
      expect {
        signed_post(payload, event: "pull_request")
      }.not_to have_enqueued_job(Preview::DeployJob)
      expect(response).to have_http_status(:ok)
    end
  end
end
