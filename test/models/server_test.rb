require "test_helper"

class ServerTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email: "server-owner@example.com", password: "password123456")
    @team = Team.create!(name: "server-team", owner: @owner)
  end

  test "valid server" do
    server = Server.new(name: "web-1", host: "10.0.0.1", team: @team)
    assert server.valid?
  end

  test "requires name" do
    server = Server.new(host: "10.0.0.1", team: @team)
    assert_not server.valid?
    assert_includes server.errors[:name], "can't be blank"
  end

  test "requires host" do
    server = Server.new(name: "web-1", team: @team)
    assert_not server.valid?
    assert_includes server.errors[:host], "can't be blank"
  end

  test "name is unique within team" do
    Server.create!(name: "web-1", host: "10.0.0.1", team: @team)
    duplicate = Server.new(name: "web-1", host: "10.0.0.2", team: @team)
    assert_not duplicate.valid?
  end

  test "defaults to port 22 and ssh_user dokku" do
    server = Server.new(name: "web-1", host: "10.0.0.1", team: @team)
    assert_equal 22, server.port
    assert_equal "dokku", server.ssh_user
  end

  test "default status is connected" do
    server = Server.new(name: "web-1", host: "10.0.0.1", team: @team)
    assert_equal "connected", server.status
  end

  test "encrypts ssh_private_key" do
    server = Server.create!(name: "enc-test", host: "10.0.0.1", team: @team, ssh_private_key: "secret-key-data")
    server.reload
    assert_equal "secret-key-data", server.ssh_private_key
  end

  test "port must be positive integer" do
    server = Server.new(name: "web-1", host: "10.0.0.1", team: @team, port: -1)
    assert_not server.valid?
    assert_includes server.errors[:port], "must be greater than 0"
  end
end
