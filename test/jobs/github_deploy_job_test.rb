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
    assert_equal "abc1234567890", @deploy.reload.commit_sha
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
    assert_includes @deploy.reload.log, "git sync failed"
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :run_streaming
    end
    DeployChannel.singleton_class.remove_method(:broadcast_to) rescue nil
  end

  test "marks deploy as timed_out on Timeout::Error" do
    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:run_streaming) { |_cmd, &_block| raise Timeout::Error, "deploy timed out" }
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

    assert_equal "timed_out", @deploy.reload.status
    assert_equal "crashed", @app.reload.status
    assert_includes @deploy.reload.log, "timed out"
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :run_streaming
    end
    DeployChannel.singleton_class.remove_method(:broadcast_to) rescue nil
  end

  test "transitions app to deploying at start" do
    @app.update!(status: :running)

    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:run_streaming) { |_cmd, &block| block.call("building\n") }
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

    assert_equal "running", @app.reload.status
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :run_streaming
    end
    DeployChannel.singleton_class.remove_method(:broadcast_to) rescue nil
  end

  test "streams deploy log output" do
    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:run_streaming) do |_cmd, &block|
        block.call("chunk one\n")
        block.call("chunk two\n")
      end
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

    log = @deploy.reload.log
    assert_includes log, "chunk one"
    assert_includes log, "chunk two"
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :run_streaming
    end
    DeployChannel.singleton_class.remove_method(:broadcast_to) rescue nil
  end
end
