require "test_helper"

class TerminalSessionTest < ActiveSupport::TestCase
  test "initializes with server" do
    server = servers(:one)
    session = TerminalSession.new(server: server)
    assert_equal server, session.server
    assert_not session.connected?
  end

  test "builds ssh options from server" do
    server = servers(:one)
    session = TerminalSession.new(server: server)
    opts = session.send(:ssh_options)
    assert_equal server.port, opts[:port]
    assert opts[:non_interactive]
  end

  test "tracks last activity for timeout" do
    server = servers(:one)
    session = TerminalSession.new(server: server)
    session.touch!
    assert_in_delta Time.current.to_f, session.last_activity_at.to_f, 1.0
  end

  test "timed_out? returns true after inactivity" do
    server = servers(:one)
    session = TerminalSession.new(server: server, timeout: 1.second)
    session.touch!
    sleep 1.1
    assert session.timed_out?
  end
end
