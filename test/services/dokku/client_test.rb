require "test_helper"

class Dokku::ClientTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "test-dokku@example.com", password: "password123456")
    @team = Team.create!(name: "Test Team", owner: @user)
    @server = Server.create!(name: "prod", host: "dokku.example.com", team: @team)
    @client = Dokku::Client.new(@server)
  end

  test "initializes with server" do
    assert_equal @server, @client.instance_variable_get(:@server)
  end

  test "raises ConnectionError on auth failure" do
    Net::SSH.stubs(:start).raises(Net::SSH::AuthenticationFailed.new("test"))
    assert_raises(Dokku::Client::ConnectionError) { @client.run("apps:list") }
    assert_equal "auth_failed", @server.reload.status
  end

  test "raises ConnectionError on connection refused" do
    Net::SSH.stubs(:start).raises(Errno::ECONNREFUSED)
    assert_raises(Dokku::Client::ConnectionError) { @client.run("apps:list") }
    assert_equal "unreachable", @server.reload.status
  end

  test "raises ConnectionError on SocketError" do
    Net::SSH.stubs(:start).raises(SocketError, "no dns")
    assert_raises(Dokku::Client::ConnectionError) { @client.run("apps:list") }
    assert_equal "unreachable", @server.reload.status
  end

  test "raises ConnectionError on ETIMEDOUT" do
    Net::SSH.stubs(:start).raises(Errno::ETIMEDOUT)
    assert_raises(Dokku::Client::ConnectionError) { @client.run("apps:list") }
  end

  # --- Success path + command-level behaviors ---

  def stub_ssh_session(output: "", error: "", exit_code: 0, exec_success: true, capture_cmd: nil)
    fake_ch = Object.new
    data_handler = ->(_, _) {}
    extended_handler = ->(_, _, _) {}
    exit_handler = ->(_, _) {}
    fake_ch.define_singleton_method(:on_data) { |&b| data_handler = b }
    fake_ch.define_singleton_method(:on_extended_data) { |&b| extended_handler = b }
    fake_ch.define_singleton_method(:on_request) { |_name, &b| exit_handler = b }
    fake_ch.define_singleton_method(:exec) do |cmd, &exec_block|
      capture_cmd&.call(cmd)
      exec_block.call(fake_ch, exec_success)
      next unless exec_success
      data_handler.call(nil, output) unless output.empty?
      extended_handler.call(nil, nil, error) unless error.empty?
      buf = Object.new
      buf.define_singleton_method(:read_long) { exit_code }
      exit_handler.call(nil, buf)
    end

    fake_channel = Object.new
    fake_channel.define_singleton_method(:wait) { true }

    fake_ssh = Object.new
    fake_ssh.define_singleton_method(:open_channel) { |&b| b.call(fake_ch); fake_channel }

    Net::SSH.stubs(:start).yields(fake_ssh)
  end

  test "run returns stripped output on success" do
    stub_ssh_session(output: "  hello  ", exit_code: 0)
    assert_equal "hello", @client.run("version")
  end

  test "run raises CommandError on non-zero exit code with stderr attached" do
    stub_ssh_session(output: "", error: "boom", exit_code: 5)
    err = assert_raises(Dokku::Client::CommandError) { @client.run("bad") }
    assert_equal 5, err.exit_code
    assert_equal "boom", err.stderr
  end

  test "run raises ConnectionError when exec fails to start" do
    stub_ssh_session(exec_success: false)
    assert_raises(Dokku::Client::ConnectionError) { @client.run("x") }
  end

  test "run sends the command raw when ssh_user is dokku" do
    @server.update!(ssh_user: "dokku")
    captured = nil
    stub_ssh_session(capture_cmd: ->(c) { captured = c })
    @client.run("apps:list")
    assert_equal "apps:list", captured
  end

  test "run prefixes with 'dokku' when ssh_user is not dokku" do
    @server.update!(ssh_user: "ubuntu")
    captured = nil
    stub_ssh_session(capture_cmd: ->(c) { captured = c })
    @client.run("apps:list")
    assert_equal "dokku apps:list", captured
  end

  test "connected? returns true when version succeeds" do
    stub_ssh_session(output: "0.35.0", exit_code: 0)
    assert @client.connected?
  end

  test "connected? returns false on ConnectionError" do
    Net::SSH.stubs(:start).raises(Errno::ECONNREFUSED)
    assert_equal false, @client.connected?
  end

  test "connected? returns false on CommandError" do
    stub_ssh_session(exit_code: 1)
    assert_equal false, @client.connected?
  end

  test "run_streaming yields chunks via the provided block" do
    chunks = []
    stub_ssh_session(output: "hello", error: "warn", exit_code: 0)
    @client.run_streaming("tail") { |data| chunks << data }
    assert_includes chunks, "hello"
    assert_includes chunks, "warn"
  end
end
