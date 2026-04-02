require "test_helper"

class SyncServerJobTest < ActiveJob::TestCase
  setup do
    @server = servers(:one)
  end

  test "sets server to syncing then connected on success" do
    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
    end

    Dokku::Apps.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_client| }
      define_method(:list) { [ "my-app-one" ] }
    end

    SyncServerJob.perform_now(@server.id)
    assert_equal "connected", @server.reload.status
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
    end
    Dokku::Apps.class_eval do
      remove_method :list
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
    end
  end

  test "creates new apps found on remote" do
    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
    end

    Dokku::Apps.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_client| }
      define_method(:list) { [ "my-app-one", "new-remote-app" ] }
    end

    assert_difference -> { @server.app_records.count }, 1 do
      SyncServerJob.perform_now(@server.id)
    end

    assert @server.app_records.find_by(name: "new-remote-app")
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
    end
    Dokku::Apps.class_eval do
      remove_method :list
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
    end
  end

  test "sets server to unreachable on connection error" do
    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
    end

    Dokku::Apps.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_client| }
      define_method(:list) { raise Dokku::Client::ConnectionError, "connection refused" }
    end

    SyncServerJob.perform_now(@server.id)
    assert_equal "unreachable", @server.reload.status
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
    end
    Dokku::Apps.class_eval do
      remove_method :list
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
    end
  end
end
