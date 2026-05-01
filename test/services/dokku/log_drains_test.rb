require "test_helper"

class Dokku::LogDrainsTest < ActiveSupport::TestCase
  class MockClient
    attr_reader :commands

    def initialize(responses = {})
      @responses = responses
      @commands = []
    end

    def run(command)
      @commands << command
      @responses[command] || ""
    end
  end

  test "add sends docker-options:add command with syslog options" do
    client = MockClient.new
    Dokku::LogDrains.new(client).add("my-app", "syslog://logs.example.com:514")
    expected = 'docker-options:add my-app deploy,run "--log-driver syslog --log-opt syslog-address=syslog://logs.example.com:514"'
    assert_equal [ expected ], client.commands
  end

  test "remove sends docker-options:remove command" do
    client = MockClient.new
    Dokku::LogDrains.new(client).remove("my-app")
    expected = 'docker-options:remove my-app deploy,run "--log-driver syslog"'
    assert_equal [ expected ], client.commands
  end

  test "remove returns nil if command raises an error" do
    client = Object.new
    def client.run(_command)
      raise StandardError, "ssh error"
    end
    result = Dokku::LogDrains.new(client).remove("my-app")
    assert_nil result
  end

  test "report sends docker-options:report command" do
    client = MockClient.new("docker-options:report my-app" => "some docker options output")
    result = Dokku::LogDrains.new(client).report("my-app")
    assert_equal "some docker options output", result
    assert_equal [ "docker-options:report my-app" ], client.commands
  end
end
