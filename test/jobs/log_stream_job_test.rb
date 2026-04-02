require "test_helper"

class LogStreamJobTest < ActiveJob::TestCase
  setup do
    @app = app_records(:one)
  end

  test "can be enqueued" do
    assert_enqueued_jobs 1 do
      LogStreamJob.perform_later(@app.id, "channel-abc")
    end
  end

  test "streams logs and broadcasts to LogChannel" do
    broadcast_calls = []

    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:run_streaming) { |_cmd, &block| block.call("log line 1\n"); block.call("log line 2\n") }
    end

    LogChannel.class_eval do
      define_singleton_method(:broadcast_to) { |_app, payload| broadcast_calls << payload }
    end

    LogStreamJob.perform_now(@app.id, "channel-abc")

    assert_equal 2, broadcast_calls.size
    assert_equal "log", broadcast_calls.first[:type]
    assert_includes broadcast_calls.first[:data], "log line 1"
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :run_streaming
    end
    LogChannel.singleton_class.remove_method(:broadcast_to) rescue nil
  end

  test "returns early when app not found" do
    assert_nothing_raised do
      LogStreamJob.perform_now(0, "channel-abc")
    end
  end

  test "broadcasts error message on ConnectionError" do
    broadcast_calls = []

    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:run_streaming) { |_cmd, &_block| raise Dokku::Client::ConnectionError, "SSH refused" }
    end

    LogChannel.class_eval do
      define_singleton_method(:broadcast_to) { |_app, payload| broadcast_calls << payload }
    end

    LogStreamJob.perform_now(@app.id, "channel-abc")

    assert_equal "error", broadcast_calls.last[:type]
    assert_includes broadcast_calls.last[:data], "SSH refused"
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :run_streaming
    end
    LogChannel.singleton_class.remove_method(:broadcast_to) rescue nil
  end
end
