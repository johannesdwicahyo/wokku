# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Webhooks::GitlabController", type: :request do
  before { @original_secret = ENV["GITLAB_WEBHOOK_SECRET"]; ENV["GITLAB_WEBHOOK_SECRET"] = "test_gitlab_webhook_secret" }
  after  { ENV["GITLAB_WEBHOOK_SECRET"] = @original_secret }

  def gitlab_post(payload, event: "Push Hook", token: "test_gitlab_webhook_secret")
    post "/webhooks/gitlab",
         params: payload,
         headers: {
           "Content-Type" => "application/json",
           "X-Gitlab-Event" => event,
           "X-Gitlab-Token" => token
         }
  end

  # ---------------------------------------------------------------------------
  # Signature / token verification
  # ---------------------------------------------------------------------------

  it "rejects request with missing token" do
    post "/webhooks/gitlab",
         params: '{"object_kind":"push"}',
         headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects request with wrong token" do
    gitlab_post('{"object_kind":"push"}', token: "wrong_secret")
    expect(response).to have_http_status(:unauthorized)
  end

  it "accepts valid token and returns ok for unknown event" do
    gitlab_post('{"object_kind":"tag_push"}', event: "Tag Push Hook")
    expect(response).to have_http_status(:ok)
  end

  # ---------------------------------------------------------------------------
  # Push events
  # ---------------------------------------------------------------------------

  context "Push Hook" do
    let!(:gitlab_app) do
      create(:app_record,
             git_provider: "gitlab",
             git_repo_full_name: "owner/gitlab-repo",
             deploy_branch: "main")
    end

    it "enqueues GitlabDeployJob for matching app" do
      payload = {
        ref: "refs/heads/main",
        checkout_sha: "abc123def456",
        project: { path_with_namespace: "owner/gitlab-repo" },
        commits: [ { message: "Fix something" } ]
      }.to_json

      expect {
        gitlab_post(payload, event: "Push Hook")
      }.to have_enqueued_job(GitlabDeployJob)
      expect(response).to have_http_status(:ok)
    end

    it "creates Deploy and Release records" do
      payload = {
        ref: "refs/heads/main",
        checkout_sha: "deadbeef1234",
        project: { path_with_namespace: "owner/gitlab-repo" },
        commits: [ { message: "feat: initial commit" } ]
      }.to_json

      expect {
        gitlab_post(payload, event: "Push Hook")
      }.to change(Deploy, :count).by(1).and change(Release, :count).by(1)
    end

    it "does not trigger for non-matching branch" do
      payload = {
        ref: "refs/heads/feature-branch",
        checkout_sha: "abc123",
        project: { path_with_namespace: "owner/gitlab-repo" },
        commits: [ { message: "WIP" } ]
      }.to_json

      expect {
        gitlab_post(payload, event: "Push Hook")
      }.not_to have_enqueued_job(GitlabDeployJob)
      expect(response).to have_http_status(:ok)
    end

    it "returns ok with missing repo without enqueueing" do
      payload = {
        ref: "refs/heads/main",
        checkout_sha: "abc123",
        project: {},
        commits: []
      }.to_json

      expect {
        gitlab_post(payload, event: "Push Hook")
      }.not_to have_enqueued_job(GitlabDeployJob)
      expect(response).to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------------
  # Merge Request Hook — routed through Preview::EventDispatcher
  # ---------------------------------------------------------------------------

  context "Merge Request Hook" do
    let!(:parent) do
      create(:app_record,
             git_provider: "gitlab",
             git_repo_full_name: "octo/repo",
             preview_enabled: true)
    end

    it "enqueues Preview::DeployJob for opened MR" do
      payload = File.read(Rails.root.join("spec/fixtures/webhooks/gitlab/merge_request_opened.json"))

      expect {
        gitlab_post(payload, event: "Merge Request Hook")
      }.to have_enqueued_job(Preview::DeployJob)
      expect(response).to have_http_status(:ok)
    end

    it "enqueues Preview::CleanupJob for merged MR" do
      # CleanupJob is only enqueued when a preview app exists for the PR
      create(:app_record, :preview, parent_app: parent, pr_number: 7)
      payload = File.read(Rails.root.join("spec/fixtures/webhooks/gitlab/merge_request_merged.json"))

      expect {
        gitlab_post(payload, event: "Merge Request Hook")
      }.to have_enqueued_job(Preview::CleanupJob)
      expect(response).to have_http_status(:ok)
    end

    it "enqueues Preview::CleanupJob for closed MR" do
      # CleanupJob is only enqueued when a preview app exists for the PR
      create(:app_record, :preview, parent_app: parent, pr_number: 7)
      payload = File.read(Rails.root.join("spec/fixtures/webhooks/gitlab/merge_request_closed.json"))

      expect {
        gitlab_post(payload, event: "Merge Request Hook")
      }.to have_enqueued_job(Preview::CleanupJob)
      expect(response).to have_http_status(:ok)
    end

    it "no-ops when no parent has the repo connected" do
      parent.update!(git_repo_full_name: "other/repo")
      payload = File.read(Rails.root.join("spec/fixtures/webhooks/gitlab/merge_request_opened.json"))

      expect {
        gitlab_post(payload, event: "Merge Request Hook")
      }.not_to have_enqueued_job(Preview::DeployJob)
      expect(response).to have_http_status(:ok)
    end
  end
end
