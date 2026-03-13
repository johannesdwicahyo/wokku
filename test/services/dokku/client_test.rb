require "test_helper"

class Dokku::ClientTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
    @team = Team.create!(name: "Test Team", owner: @user)
    @server = Server.create!(name: "prod", host: "dokku.example.com", team: @team)
    @client = Dokku::Client.new(@server)
  end

  test "initializes with server" do
    assert_equal @server, @client.instance_variable_get(:@server)
  end

  test "raises ConnectionError on auth failure" do
    original = Net::SSH.method(:start)
    Net::SSH.define_singleton_method(:start) { |*_args, **_opts| raise Net::SSH::AuthenticationFailed.new("test") }
    begin
      assert_raises(Dokku::Client::ConnectionError) { @client.run("apps:list") }
      assert_equal "auth_failed", @server.reload.status
    ensure
      Net::SSH.define_singleton_method(:start, original)
    end
  end

  test "raises ConnectionError on connection refused" do
    original = Net::SSH.method(:start)
    Net::SSH.define_singleton_method(:start) { |*_args, **_opts| raise Errno::ECONNREFUSED }
    begin
      assert_raises(Dokku::Client::ConnectionError) { @client.run("apps:list") }
      assert_equal "unreachable", @server.reload.status
    ensure
      Net::SSH.define_singleton_method(:start, original)
    end
  end
end
