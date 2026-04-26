require "test_helper"

class DatabaseProvisionerTest < ActiveSupport::TestCase
  class StubClient
    attr_reader :calls, :stdin_calls
    def initialize
      @calls = []
      @stdin_calls = []
    end
    def run(cmd, timeout: 30, stdin: nil)
      @calls << cmd
      @stdin_calls << stdin if stdin
      ""
    end
  end

  setup do
    @app = app_records(:one)
    @server = @app.server
    @client = StubClient.new
  end

  test "dedicated tier provisions via Dokku::Databases and links to app" do
    provisioner = DatabaseProvisioner.new(
      app: @app, service_type: "postgres", tier: "mini", client: @client
    )

    assert_difference -> { DatabaseService.count } => 1,
                      -> { AppDatabase.count } => 1 do
      @db = provisioner.call
    end

    refute @db.shared?
    assert_equal "mini", @db.tier_name
    assert @client.calls.any? { |c| c.start_with?("postgres:create") }
    assert @client.calls.any? { |c| c.start_with?("postgres:link") }
  end

  test "shared_free tier routes through Dokku::SharedPostgres and sets DATABASE_URL via config" do
    provisioner = DatabaseProvisioner.new(
      app: @app, service_type: "postgres", tier: "shared_free", client: @client
    )

    # Parent host row gets created alongside the tenant row, so +2
    assert_difference -> { DatabaseService.count } => 2,
                      -> { AppDatabase.count } => 1 do
      @db = provisioner.call
    end

    assert @db.shared?
    assert_equal "shared_free", @db.tier_name
    assert_match(/\Au_/, @db.shared_role_name)
    assert_match(/\Adb_/, @db.shared_db_name)
    assert_equal 150, @db.storage_mb_quota
    assert_equal 5, @db.connection_limit

    # DATABASE_URL was set on the app via dokku config:set
    assert @client.calls.any? { |c| c.include?("config:set") }, "should set DATABASE_URL via config"

    # Parent row is linked
    assert_equal "wokku-shared-free", @db.parent_service.name
  end

  test "shared_free tier is postgres-only" do
    provisioner = DatabaseProvisioner.new(
      app: @app, service_type: "mysql", tier: "shared_free", client: @client
    )
    # mysql + shared_free falls through to dedicated (tier check requires postgres)
    # so this actually provisions a dedicated mysql. Verify it didn't try the shared path.
    @db = provisioner.call
    refute @db.shared?
    refute @client.stdin_calls.any? { |s| s.to_s.include?("CREATE ROLE") }
  end

  test "destroy! for shared tenant tears down role + db via SharedPostgres" do
    db = DatabaseProvisioner.new(
      app: @app, service_type: "postgres", tier: "shared_free", client: @client
    ).call
    @client.calls.clear
    @client.stdin_calls.clear

    DatabaseProvisioner.destroy!(database_service: db, client: @client)

    assert @client.stdin_calls.any? { |s| s.include?("DROP DATABASE") },
      "should drop the shared tenant's database"
    assert @client.stdin_calls.any? { |s| s.include?("DROP ROLE") },
      "should drop the shared tenant's role"
    assert @client.calls.any? { |c| c.include?("config:unset") && c.include?("DATABASE_URL") },
      "should unset DATABASE_URL on the app so it doesn't keep a stale pointer"
  end

  test "destroy! for dedicated calls Dokku::Databases.destroy" do
    db = DatabaseProvisioner.new(
      app: @app, service_type: "postgres", tier: "mini", client: @client
    ).call
    @client.calls.clear

    DatabaseProvisioner.destroy!(database_service: db, client: @client)

    assert @client.calls.any? { |c| c.start_with?("postgres:destroy") }
  end
end
