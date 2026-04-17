require "test_helper"

class Dokku::AclTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :calls
    def initialize(responses = {})
      @responses = responses
      @calls = []
    end
    def run(cmd)
      @calls << cmd
      raise Dokku::Client::CommandError.new("boom") if @responses[:raise_on] && cmd.start_with?(@responses[:raise_on])
      @responses[:output] || ""
    end
  end

  setup do
    @client = FakeClient.new
    @acl = Dokku::Acl.new(@client)
  end

  test "add runs acl:add with escaped args" do
    @acl.add("my-app", "user-42")
    assert_equal "acl:add my-app user-42", @client.calls.first
  end

  test "add escapes shell-unsafe names" do
    @acl.add("app $(rm)", "user;rm")
    assert_match(/acl:add /, @client.calls.first)
    assert_no_match(/\$\(rm\)/, @client.calls.first)
  end

  test "remove runs acl:remove" do
    @acl.remove("app", "user-1")
    assert_equal "acl:remove app user-1", @client.calls.first
  end

  test "list returns non-empty lines" do
    @client = FakeClient.new(output: "alice\n\nbob\n")
    @acl = Dokku::Acl.new(@client)
    assert_equal %w[alice bob], @acl.list("app")
  end

  test "grant_team_apps continues after per-app CommandError" do
    @client = FakeClient.new(raise_on: "acl:add bad-app")
    @acl = Dokku::Acl.new(@client)
    apps = [ OpenStruct.new(name: "good-app"), OpenStruct.new(name: "bad-app"), OpenStruct.new(name: "another") ]
    assert_nothing_raised { @acl.grant_team_apps("user-1", apps) }
    assert_equal 3, @client.calls.length
  end

  test "revoke_all continues after CommandError" do
    @client = FakeClient.new(raise_on: "acl:remove bad")
    @acl = Dokku::Acl.new(@client)
    apps = [ OpenStruct.new(name: "good"), OpenStruct.new(name: "bad"), OpenStruct.new(name: "other") ]
    assert_nothing_raised { @acl.revoke_all("user-1", apps) }
    assert_equal 3, @client.calls.length
  end
end
