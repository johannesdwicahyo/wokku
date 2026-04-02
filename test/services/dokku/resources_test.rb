require "test_helper"

class Dokku::ResourcesTest < ActiveSupport::TestCase
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

  test "apply_limits sends correct resource:limit command" do
    client = MockClient.new
    resources = Dokku::Resources.new(client)
    resources.apply_limits("my-app", memory_mb: 512, cpu_shares: 256)
    assert_equal [ "resource:limit --memory 512 --cpu 256 my-app" ], client.commands
  end

  test "apply_reservation sends correct resource:reserve command with half memory" do
    client = MockClient.new
    resources = Dokku::Resources.new(client)
    resources.apply_reservation("my-app", memory_mb: 512)
    assert_equal [ "resource:reserve --memory 256 my-app" ], client.commands
  end

  test "apply_reservation uses integer division for memory" do
    client = MockClient.new
    resources = Dokku::Resources.new(client)
    resources.apply_reservation("my-app", memory_mb: 100)
    assert_equal [ "resource:reserve --memory 50 my-app" ], client.commands
  end

  test "report sends resource:report command" do
    output = <<~OUTPUT
      =====> my-app resource information
          App Memory Limit: 512
          App Cpu Limit:    256
    OUTPUT
    client = MockClient.new("resource:report my-app" => output)
    resources = Dokku::Resources.new(client)
    result = resources.report("my-app")
    assert_equal [ "resource:report my-app" ], client.commands
    assert_instance_of Hash, result
  end

  test "report parses key-value pairs from output" do
    output = "  App Memory Limit: 512\n  App Cpu Limit: 256\n"
    client = MockClient.new("resource:report my-app" => output)
    resources = Dokku::Resources.new(client)
    result = resources.report("my-app")
    assert_equal "512", result["app_memory_limit"]
    assert_equal "256", result["app_cpu_limit"]
  end

  test "report skips header lines starting with =" do
    output = "=====> my-app resource information\n  App Memory Limit: 128\n"
    client = MockClient.new("resource:report my-app" => output)
    resources = Dokku::Resources.new(client)
    result = resources.report("my-app")
    assert_not result.key?("=====")
    assert_equal "128", result["app_memory_limit"]
  end

  test "report returns empty hash for empty output" do
    client = MockClient.new("resource:report empty-app" => "")
    resources = Dokku::Resources.new(client)
    result = resources.report("empty-app")
    assert_equal({}, result)
  end
end
