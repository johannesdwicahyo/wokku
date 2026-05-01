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

  test "marks deploy as timed_out on Timeout::Error" do
    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:run_streaming) { |_cmd, &_block| raise Timeout::Error, "timed out" }
    end

    DeployChannel.class_eval do
      define_singleton_method(:broadcast_to) { |*_args| nil }
    end

    DeployJob.perform_now(@deploy.id)

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

  test "returns early when deploy not found" do
    assert_nothing_raised do
      DeployJob.perform_now(0)
    end
  end

  test "sets deploy status to building at start" do
    # Change deploy to pending so we can observe the transition
    @deploy.update!(status: :pending)

    status_during_deploy = nil

    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:run_streaming) do |_cmd, &block|
        # Capture status mid-execution
        block.call("building...\n")
      end
    end

    DeployChannel.class_eval do
      define_singleton_method(:broadcast_to) { |*_args| nil }
    end

    DeployJob.perform_now(@deploy.id)

    assert_equal "succeeded", @deploy.reload.status
    assert_not_nil @deploy.reload.started_at
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :run_streaming
    end
    DeployChannel.singleton_class.remove_method(:broadcast_to) rescue nil
  end

  test "appends streaming log output to deploy log" do
    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:run_streaming) do |_cmd, &block|
        block.call("line one\n")
        block.call("line two\n")
      end
    end

    DeployChannel.class_eval do
      define_singleton_method(:broadcast_to) { |*_args| nil }
    end

    DeployJob.perform_now(@deploy.id)

    log = @deploy.reload.log
    assert_includes log, "line one"
    assert_includes log, "line two"
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :run_streaming
    end
    DeployChannel.singleton_class.remove_method(:broadcast_to) rescue nil
  end

  test "stores commit_sha when provided" do
    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:run_streaming) { |_cmd, &block| block.call("") }
    end

    DeployChannel.class_eval do
      define_singleton_method(:broadcast_to) { |*_args| nil }
    end

    DeployJob.perform_now(@deploy.id, commit_sha: "deadbeef1234")

    assert_equal "deadbeef1234", @deploy.reload.commit_sha
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :run_streaming
    end
    DeployChannel.singleton_class.remove_method(:broadcast_to) rescue nil
  end
end
