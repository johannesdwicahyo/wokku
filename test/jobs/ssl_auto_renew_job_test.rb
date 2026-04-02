require "test_helper"

class SslAutoRenewJobTest < ActiveJob::TestCase
  test "can be enqueued" do
    assert_enqueued_jobs 1 do
      SslAutoRenewJob.perform_later
    end
  end

  test "calls letsencrypt:auto-renew for each connected server" do
    server = servers(:one)
    server.update!(status: :connected)

    commands_run = []

    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:run) { |cmd| commands_run << cmd }
    end

    SslAutoRenewJob.perform_now

    assert_includes commands_run, "letsencrypt:auto-renew"
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :run
    end
  end

  test "skips non-connected servers" do
    Server.update_all(status: :unreachable)

    commands_run = []
    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
      define_method(:run) { |cmd| commands_run << cmd }
    end

    SslAutoRenewJob.perform_now

    assert_empty commands_run
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :run
    end
    Server.update_all(status: :connected)
  end

  test "continues for other servers when one raises an error" do
    server1 = servers(:one)
    server2 = servers(:two)
    server1.update!(status: :connected)
    server2.update!(status: :connected)

    call_count = 0
    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| @server_obj = _server }
      define_method(:run) do |_cmd|
        call_count += 1
        raise "SSL renew failed" if call_count == 1
      end
    end

    assert_nothing_raised do
      SslAutoRenewJob.perform_now
    end

    assert_equal 2, call_count
  ensure
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :run
    end
  end
end
