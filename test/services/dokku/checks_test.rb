require "test_helper"

class Dokku::ChecksTest < ActiveSupport::TestCase
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

  test "report sends checks:report command" do
    client = MockClient.new("checks:report my-app" => "")
    Dokku::Checks.new(client).report("my-app")
    assert_equal [ "checks:report my-app" ], client.commands
  end

  test "report parses key-value pairs from output" do
    output = "  Checks Disabled: false\n  Checks Wait:     5\n  Checks Timeout:  5\n"
    client = MockClient.new("checks:report my-app" => output)
    result = Dokku::Checks.new(client).report("my-app")
    assert_equal "false", result["checks_disabled"]
    assert_equal "5", result["checks_wait"]
    assert_equal "5", result["checks_timeout"]
  end

  test "report returns empty hash for empty output" do
    client = MockClient.new("checks:report empty-app" => "")
    result = Dokku::Checks.new(client).report("empty-app")
    assert_equal({}, result)
  end

  test "report skips lines without a colon" do
    output = "=====> my-app checks information\n  Checks Disabled: true\n"
    client = MockClient.new("checks:report my-app" => output)
    result = Dokku::Checks.new(client).report("my-app")
    assert_equal "true", result["checks_disabled"]
    # header line should not produce a key
    assert_equal 1, result.size
  end

  test "enable sends checks:enable command" do
    client = MockClient.new
    Dokku::Checks.new(client).enable("my-app")
    assert_equal [ "checks:enable my-app" ], client.commands
  end

  test "disable sends checks:disable command" do
    client = MockClient.new
    Dokku::Checks.new(client).disable("my-app")
    assert_equal [ "checks:disable my-app" ], client.commands
  end

  test "set sends checks:set command with key and value" do
    client = MockClient.new
    Dokku::Checks.new(client).set("my-app", "CHECKS_WAIT", "10")
    assert_equal [ "checks:set my-app CHECKS_WAIT 10" ], client.commands
  end
end
