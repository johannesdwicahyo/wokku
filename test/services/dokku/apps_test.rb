require "test_helper"

class Dokku::AppsTest < ActiveSupport::TestCase
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

  test "list parses app names" do
    client = MockClient.new("apps:list" => "=====> My Apps\napp-one\napp-two\n")
    apps = Dokku::Apps.new(client)
    result = apps.list
    assert_equal [ "app-one", "app-two" ], result
    assert_equal [ "apps:list" ], client.commands
  end

  test "create calls apps:create" do
    client = MockClient.new("apps:create app-one" => "Creating app-one...")
    apps = Dokku::Apps.new(client)
    apps.create("app-one")
    assert_equal [ "apps:create app-one" ], client.commands
  end
end
