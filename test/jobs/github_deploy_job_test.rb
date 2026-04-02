require "test_helper"

class GithubDeployJobTest < ActiveJob::TestCase
  setup do
    @app = app_records(:one)
    @deploy = deploys(:one)
  end

  test "can be enqueued" do
    assert_enqueued_jobs 1 do
      GithubDeployJob.perform_later(
        app_id: @app.id,
        deploy_id: @deploy.id,
        repo_full_name: "owner/repo",
        branch: "main",
        commit_sha: "abc123"
      )
    end
  end

  test "marks deploy as succeeded on successful run" do
    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:run_streaming) { |_cmd, &block| block.call("git sync output\n") }
    end

    DeployChannel.class_eval do
      define_singleton_method(:broadcast_to) { |*_args| nil }
    end

    GithubDeployJob.perform_now(
      app_id: @app.id,
      deploy_id: @deploy.id,
      repo_full_name: "owner/repo",
      branch: "main",
      commit_sha: "abc1234567890"
    )

    assert_equal "succeeded", @deploy.reload.status
    assert_equal "running", @app.reload.status
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :run_streaming
    end
    DeployChannel.singleton_class.remove_method(:broadcast_to) rescue nil
  end

  test "marks deploy as failed on CommandError" do
    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:run_streaming) { |_cmd, &_block| raise Dokku::Client::CommandError, "git sync failed" }
    end

    DeployChannel.class_eval do
      define_singleton_method(:broadcast_to) { |*_args| nil }
    end

    GithubDeployJob.perform_now(
      app_id: @app.id,
      deploy_id: @deploy.id,
      repo_full_name: "owner/repo",
      branch: "main",
      commit_sha: "abc123"
    )

    assert_equal "failed", @deploy.reload.status
    assert_equal "crashed", @app.reload.status
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :run_streaming
    end
    DeployChannel.singleton_class.remove_method(:broadcast_to) rescue nil
  end
end
