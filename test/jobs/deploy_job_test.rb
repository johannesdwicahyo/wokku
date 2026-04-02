require "test_helper"

class DeployJobTest < ActiveJob::TestCase
  setup do
    @deploy = deploys(:one)
    @app = @deploy.app_record
  end

  test "can be enqueued" do
    assert_enqueued_jobs 1 do
      DeployJob.perform_later(@deploy.id)
    end
  end

  test "marks deploy as succeeded on successful run" do
    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:run_streaming) { |_cmd, &block| block.call("deploy output\n") }
    end

    DeployChannel.class_eval do
      define_singleton_method(:broadcast_to) { |*_args| nil }
    end

    DeployJob.perform_now(@deploy.id)

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
      define_method(:run_streaming) { |_cmd, &_block| raise Dokku::Client::CommandError, "command failed" }
    end

    DeployChannel.class_eval do
      define_singleton_method(:broadcast_to) { |*_args| nil }
    end

    DeployJob.perform_now(@deploy.id)

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

  test "returns early when deploy not found" do
    assert_nothing_raised do
      DeployJob.perform_now(0)
    end
  end
end
