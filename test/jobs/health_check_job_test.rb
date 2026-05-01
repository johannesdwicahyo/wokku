require "test_helper"

class HealthCheckJobTest < ActiveJob::TestCase
  setup do
    @server = servers(:one)
  end

  test "sets server status to connected when client connects" do
    mock_client = Object.new
    mock_client.define_singleton_method(:connected?) { true }

    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:connected?) { true }
    end

    HealthCheckJob.perform_now(@server.id)
    assert_equal "connected", @server.reload.status
  ensure
    Dokku::Client.class_eval do
      remove_method :connected?
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
    end
  end

  test "sets server status to unreachable when client cannot connect" do
    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:connected?) { false }
    end

    HealthCheckJob.perform_now(@server.id)
    assert_equal "unreachable", @server.reload.status
  ensure
    Dokku::Client.class_eval do
      remove_method :connected?
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
    end
  end

  test "sets server status to unreachable on connection error" do
    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:connected?) { raise Dokku::Client::ConnectionError, "connection refused" }
    end

    HealthCheckJob.perform_now(@server.id)
    assert_equal "unreachable", @server.reload.status
  ensure
    Dokku::Client.class_eval do
      remove_method :connected?
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
    end
  end
end
