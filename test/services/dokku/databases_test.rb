require "test_helper"

class Dokku::DatabasesTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :calls
    def initialize(output = "")
      @output = output
      @calls = []
    end
    def run(cmd)
      @calls << cmd
      @output
    end
  end

  test "list returns non-empty non-header lines" do
    client = FakeClient.new("=====> postgres services\npg1\n\npg2\n")
    assert_equal %w[pg1 pg2], Dokku::Databases.new(client).list("postgres")
  end

  test "create runs <plugin>:create with escaped name" do
    client = FakeClient.new
    Dokku::Databases.new(client).create("postgres", "my-db")
    assert_equal "postgres:create my-db", client.calls.first
  end

  test "destroy forces teardown" do
    client = FakeClient.new
    Dokku::Databases.new(client).destroy("redis", "cache")
    assert_match(/redis:destroy cache --force/, client.calls.first)
  end

  test "link joins db and app names" do
    client = FakeClient.new
    Dokku::Databases.new(client).link("postgres", "shared-pg", "my-app")
    assert_equal "postgres:link shared-pg my-app", client.calls.first
  end

  test "unlink issues <plugin>:unlink" do
    client = FakeClient.new
    Dokku::Databases.new(client).unlink("postgres", "shared-pg", "my-app")
    assert_equal "postgres:unlink shared-pg my-app", client.calls.first
  end

  test "mongodb maps to 'mongo' plugin name" do
    client = FakeClient.new
    Dokku::Databases.new(client).create("mongodb", "doc-db")
    assert_match(/^mongo:create doc-db$/, client.calls.first)
  end

  test "info parses colon-delimited key/value lines into a hash" do
    client = FakeClient.new(<<~OUT)
      =====> my-db info
      Config dir:          /var/lib/dokku/postgres
      Status:              running
    OUT
    report = Dokku::Databases.new(client).info("postgres", "my-db")
    assert_equal "running", report["status"]
  end

  test "unsupported service type raises" do
    client = FakeClient.new
    assert_raises(ArgumentError) { Dokku::Databases.new(client).create("unknown", "x") }
  end
end
