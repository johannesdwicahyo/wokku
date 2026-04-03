require "test_helper"

class Webhooks::GithubControllerTest < ActionDispatch::IntegrationTest
  def signed_post(payload, event: "push", secret: webhook_secret)
    sig = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
    post "/webhooks/github",
      params: payload,
      headers: {
        "Content-Type" => "application/json",
        "X-GitHub-Event" => event,
        "X-Hub-Signature-256" => sig
      }
  end

  def webhook_secret
    # Use a known secret for tests regardless of env
    @webhook_secret ||= begin
      secret = GithubApp::WEBHOOK_SECRET.presence || "test_webhook_secret"
      # Override WEBHOOK_SECRET for all tests that need valid signatures
      if GithubApp::WEBHOOK_SECRET.blank?
        GithubApp.send(:remove_const, :WEBHOOK_SECRET) rescue nil
        GithubApp.const_set(:WEBHOOK_SECRET, "test_webhook_secret")
        @overrode_secret = true
      end
      secret
    end
  end

  teardown do
    if @overrode_secret
      GithubApp.send(:remove_const, :WEBHOOK_SECRET) rescue nil
      GithubApp.const_set(:WEBHOOK_SECRET, nil)
    end
  end

  test "rejects unsigned webhook" do
    post "/webhooks/github", params: "{}", headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
  end

  test "rejects webhook with wrong signature" do
    payload = '{"zen":"test"}'
    post "/webhooks/github",
      params: payload,
      headers: {
        "Content-Type" => "application/json",
        "X-GitHub-Event" => "ping",
        "X-Hub-Signature-256" => "sha256=invalidsignature"
      }
    assert_response :unauthorized
  end

  test "accepts ping event with valid signature" do
    payload = '{"zen":"test"}'
    signed_post(payload, event: "ping")
    assert_response :ok
  end

  test "accepts unknown event with valid signature" do
    payload = '{"action":"unknown"}'
    signed_post(payload, event: "create")
    assert_response :ok
  end

  test "push event enqueues GithubDeployJob for matching app" do
    app = app_records(:one)
    app.update!(github_repo_full_name: "owner/matching-repo", deploy_branch: "main")

    payload = {
      ref: "refs/heads/main",
      repository: { full_name: "owner/matching-repo" },
      head_commit: { id: "abc123def456", message: "Fix bug" }
    }.to_json

    assert_enqueued_jobs 1, only: GithubDeployJob do
      signed_post(payload, event: "push")
    end
    assert_response :ok
  ensure
    app.update!(github_repo_full_name: nil)
  end

  test "push event creates deploy and release records" do
    app = app_records(:one)
    app.update!(github_repo_full_name: "owner/push-test-repo", deploy_branch: "main")

    payload = {
      ref: "refs/heads/main",
      repository: { full_name: "owner/push-test-repo" },
      head_commit: { id: "deadbeef1234", message: "feat: new feature" }
    }.to_json

    assert_difference "Deploy.count", 1 do
      assert_difference "Release.count", 1 do
        signed_post(payload, event: "push")
      end
    end
  ensure
    app.update!(github_repo_full_name: nil)
  end

  test "push event does not trigger for non-matching branch" do
    app = app_records(:one)
    app.update!(github_repo_full_name: "owner/branch-test-repo", deploy_branch: "main")

    payload = {
      ref: "refs/heads/feature-branch",
      repository: { full_name: "owner/branch-test-repo" },
      head_commit: { id: "abc123", message: "WIP" }
    }.to_json

    assert_no_enqueued_jobs only: GithubDeployJob do
      signed_post(payload, event: "push")
    end
    assert_response :ok
  ensure
    app.update!(github_repo_full_name: nil)
  end

  test "push event with missing repo returns ok without enqueueing" do
    payload = {
      ref: "refs/heads/main",
      repository: {},
      head_commit: { id: "abc123", message: "test" }
    }.to_json

    assert_no_enqueued_jobs only: GithubDeployJob do
      signed_post(payload, event: "push")
    end
    assert_response :ok
  end

  test "pull_request opened event enqueues PrPreviewDeployJob" do
    app = app_records(:one)
    app.update!(github_repo_full_name: "owner/pr-test-repo")

    payload = {
      action: "opened",
      pull_request: {
        number: 42,
        title: "My Feature",
        head: { ref: "feature-branch", sha: "abc123" }
      },
      repository: { full_name: "owner/pr-test-repo" }
    }.to_json

    assert_enqueued_jobs 1, only: PrPreviewDeployJob do
      signed_post(payload, event: "pull_request")
    end
    assert_response :ok
  ensure
    app.update!(github_repo_full_name: nil)
  end

  test "pull_request synchronize event enqueues PrPreviewDeployJob" do
    app = app_records(:one)
    app.update!(github_repo_full_name: "owner/pr-sync-repo")

    payload = {
      action: "synchronize",
      pull_request: {
        number: 10,
        title: "Sync PR",
        head: { ref: "feature", sha: "sha999" }
      },
      repository: { full_name: "owner/pr-sync-repo" }
    }.to_json

    assert_enqueued_jobs 1, only: PrPreviewDeployJob do
      signed_post(payload, event: "pull_request")
    end
  ensure
    app.update!(github_repo_full_name: nil)
  end

  test "pull_request closed event enqueues PrPreviewCleanupJob" do
    app = app_records(:one)
    app.update!(github_repo_full_name: "owner/pr-close-repo")

    payload = {
      action: "closed",
      pull_request: {
        number: 7,
        title: "Closed PR",
        head: { ref: "feature", sha: "sha000" }
      },
      repository: { full_name: "owner/pr-close-repo" }
    }.to_json

    assert_enqueued_jobs 1, only: PrPreviewCleanupJob do
      signed_post(payload, event: "pull_request")
    end
  ensure
    app.update!(github_repo_full_name: nil)
  end

  test "pull_request event returns ok when no matching apps" do
    payload = {
      action: "opened",
      pull_request: {
        number: 99,
        title: "Orphan PR",
        head: { ref: "feature", sha: "sha" }
      },
      repository: { full_name: "nobody/nonexistent-repo" }
    }.to_json

    assert_no_enqueued_jobs only: PrPreviewDeployJob do
      signed_post(payload, event: "pull_request")
    end
    assert_response :ok
  end
end
