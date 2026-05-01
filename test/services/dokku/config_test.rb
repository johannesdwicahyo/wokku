require "test_helper"

class Dokku::ConfigTest < ActiveSupport::TestCase
  class MockClient
    attr_reader :commands
    def initialize; @commands = []; end
    def run(cmd); @commands << cmd; ""; end
  end

  test "set passes --no-restart by default to skip the post-write rebuild" do
    client = MockClient.new
    Dokku::Config.new(client).set("my-app", { "FOO" => "bar" })
    assert_match(/\Aconfig:set --no-restart my-app FOO=bar\z/, client.commands.first)
  end

  test "set with restart: true omits the flag, letting Dokku rebuild" do
    client = MockClient.new
    Dokku::Config.new(client).set("my-app", { "FOO" => "bar" }, restart: true)
    refute_match(/--no-restart/, client.commands.first)
    assert_match(/\Aconfig:set my-app FOO=bar\z/, client.commands.first)
  end

  test "unset defaults to --no-restart as well" do
    client = MockClient.new
    Dokku::Config.new(client).unset("my-app", "FOO")
    assert_match(/\Aconfig:unset --no-restart my-app FOO\z/, client.commands.first)
  end
end
