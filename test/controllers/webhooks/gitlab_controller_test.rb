require "test_helper"

class Webhooks::GitlabControllerTest < ActionDispatch::IntegrationTest
  GITLAB_SECRET = "test_gitlab_webhook_secret"

  setup do
    @original_secret = ENV["GITLAB_WEBHOOK_SECRET"]
    ENV["GITLAB_WEBHOOK_SECRET"] = GITLAB_SECRET
  end

  teardown do
    ENV["GITLAB_WEBHOOK_SECRET"] = @original_secret
  end

  def gitlab_post(payload, event: "Push Hook", token: GITLAB_SECRET)
    post "/webhooks/gitlab",
      params: payload,
      headers: {
        "Content-Type" => "application/json",
        "X-Gitlab-Event" => event,
        "X-Gitlab-Token" => token
      }
  end

  test "rejects request with missing token" do
    post "/webhooks/gitlab",
      params: '{"object_kind":"push"}',
      headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
  end

  test "rejects request with wrong token" do
    gitlab_post('{"object_kind":"push"}', token: "wrong_secret")
    assert_response :unauthorized
  end

  test "accepts valid token and returns ok for unknown event" do
    gitlab_post('{"object_kind":"tag_push"}', event: "Tag Push Hook")
    assert_response :ok
  end

  test "push event enqueues GitlabDeployJob for matching app" do
    app = app_records(:one)
    app.update!(git_provider: "gitlab", git_repo_full_name: "owner/gitlab-repo", deploy_branch: "main")

    payload = {
      ref: "refs/heads/main",
      checkout_sha: "abc123def456",
      project: { path_with_namespace: "owner/gitlab-repo" },
      commits: [ { message: "Fix something" } ]
    }.to_json

    assert_enqueued_jobs 1, only: GitlabDeployJob do
      gitlab_post(payload, event: "Push Hook")
    end
    assert_response :ok
  ensure
    app.update!(git_provider: nil, git_repo_full_name: nil)
  end

  test "push event creates deploy and release records" do
    app = app_records(:one)
    app.update!(git_provider: "gitlab", git_repo_full_name: "owner/gitlab-push-test", deploy_branch: "main")

    payload = {
      ref: "refs/heads/main",
      checkout_sha: "deadbeef1234",
      project: { path_with_namespace: "owner/gitlab-push-test" },
      commits: [ { message: "feat: initial commit" } ]
    }.to_json

    assert_difference "Deploy.count", 1 do
      assert_difference "Release.count", 1 do
        gitlab_post(payload, event: "Push Hook")
      end
    end
  ensure
    app.update!(git_provider: nil, git_repo_full_name: nil)
  end

  test "push event does not trigger for non-matching branch" do
    app = app_records(:one)
    app.update!(git_provider: "gitlab", git_repo_full_name: "owner/gitlab-branch-test", deploy_branch: "main")

    payload = {
      ref: "refs/heads/feature-branch",
      checkout_sha: "abc123",
      project: { path_with_namespace: "owner/gitlab-branch-test" },
      commits: [ { message: "WIP" } ]
    }.to_json

    assert_no_enqueued_jobs only: GitlabDeployJob do
      gitlab_post(payload, event: "Push Hook")
    end
    assert_response :ok
  ensure
    app.update!(git_provider: nil, git_repo_full_name: nil)
  end

  test "push event with missing repo returns ok without enqueueing" do
    payload = {
      ref: "refs/heads/main",
      checkout_sha: "abc123",
      project: {},
      commits: []
    }.to_json

    assert_no_enqueued_jobs only: GitlabDeployJob do
      gitlab_post(payload, event: "Push Hook")
    end
    assert_response :ok
  end

  test "merge request opened event enqueues PrPreviewDeployJob" do
    app = app_records(:one)
    app.update!(git_provider: "gitlab", git_repo_full_name: "owner/gitlab-mr-repo")

    payload = {
      object_attributes: {
        action: "open",
        iid: 5,
        title: "New Feature",
        source_branch: "feature-x",
        last_commit: { id: "sha123" }
      },
      project: { path_with_namespace: "owner/gitlab-mr-repo" }
    }.to_json

    assert_enqueued_jobs 1, only: PrPreviewDeployJob do
      gitlab_post(payload, event: "Merge Request Hook")
    end
    assert_response :ok
  ensure
    app.update!(git_provider: nil, git_repo_full_name: nil)
  end

  test "merge request merged event enqueues PrPreviewCleanupJob" do
    app = app_records(:one)
    app.update!(git_provider: "gitlab", git_repo_full_name: "owner/gitlab-mr-close")

    payload = {
      object_attributes: {
        action: "merge",
        iid: 3,
        title: "Done",
        source_branch: "feature-y",
        last_commit: { id: "sha999" }
      },
      project: { path_with_namespace: "owner/gitlab-mr-close" }
    }.to_json

    assert_enqueued_jobs 1, only: PrPreviewCleanupJob do
      gitlab_post(payload, event: "Merge Request Hook")
    end
    assert_response :ok
  ensure
    app.update!(git_provider: nil, git_repo_full_name: nil)
  end
end
