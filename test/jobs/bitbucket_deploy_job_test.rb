require "test_helper"

class BitbucketDeployJobTest < ActiveJob::TestCase
  setup do
    @app = app_records(:one)
    @deploy = deploys(:one)
    Dokku::Client.any_instance.stubs(:run_streaming) { |_cmd, &block| block.call("ok\n") }
    DeployChannel.stubs(:broadcast_to).returns(nil)
  end

  def enqueue_args
    {
      app_id: @app.id,
      deploy_id: @deploy.id,
      repo_full_name: "team/repo",
      branch: "main",
      commit_sha: "abc1234567"
    }
  end

  test "marks deploy as succeeded on happy path" do
    BitbucketDeployJob.perform_now(**enqueue_args)
    assert_equal "succeeded", @deploy.reload.status
    assert_equal "running", @app.reload.status
  end

  test "enqueues PostDeploySetupJob after success" do
    assert_enqueued_with(job: PostDeploySetupJob, args: [ @app.id ]) do
      BitbucketDeployJob.perform_now(**enqueue_args)
    end
  end

  test "marks deploy failed on Dokku CommandError" do
    Dokku::Client.any_instance.stubs(:run_streaming).raises(Dokku::Client::CommandError.new("build failed"))
    BitbucketDeployJob.perform_now(**enqueue_args)
    assert_equal "failed", @deploy.reload.status
  end

  test "marks deploy timed_out on Timeout::Error" do
    Dokku::Client.any_instance.stubs(:run_streaming).raises(Timeout::Error, "slow")
    BitbucketDeployJob.perform_now(**enqueue_args)
    assert_equal "timed_out", @deploy.reload.status
  end
end
