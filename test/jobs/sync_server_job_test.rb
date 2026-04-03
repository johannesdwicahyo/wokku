require "test_helper"

class SyncServerJobTest < ActiveJob::TestCase
  setup do
    @server = servers(:one)

    Dokku::Client.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_server| }
    end

    Dokku::Apps.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_client| }
      define_method(:list) { [] }
    end

    Dokku::Domains.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_client| }
      define_method(:list) { |_name| [] }
    end

    Dokku::Databases.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_client| }
      define_method(:list) { |_type| [] }
      define_method(:info) { |_type, _name| { "links" => "" } }
    end
  end

  teardown do
    Dokku::Client.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
    end rescue nil

    Dokku::Apps.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method(:list) if method_defined?(:list) && instance_method(:list).owner == self
    end rescue nil

    Dokku::Domains.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method(:list) if method_defined?(:list) && instance_method(:list).owner == self
    end rescue nil

    Dokku::Databases.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      [ :list, :info ].each do |m|
        remove_method(m) if method_defined?(m) && instance_method(m).owner == self
      end
    end rescue nil
  end

  test "sets server to syncing then connected on success" do
    Dokku::Apps.class_eval { define_method(:list) { [ "my-app-one" ] } }

    SyncServerJob.perform_now(@server.id)
    assert_equal "connected", @server.reload.status
  end

  test "creates new apps found on remote" do
    Dokku::Apps.class_eval { define_method(:list) { [ "my-app-one", "new-remote-app" ] } }

    assert_difference -> { @server.app_records.count }, 1 do
      SyncServerJob.perform_now(@server.id)
    end

    assert @server.app_records.find_by(name: "new-remote-app")
  end

  test "removes apps that no longer exist remotely" do
    # Fixture has my-app-one; remote returns empty list → local app should be removed
    Dokku::Apps.class_eval { define_method(:list) { [] } }

    assert_difference -> { @server.app_records.count }, -1 do
      SyncServerJob.perform_now(@server.id)
    end

    assert_nil @server.app_records.find_by(name: "my-app-one")
  end

  test "sets server to unreachable on connection error" do
    Dokku::Apps.class_eval { define_method(:list) { raise Dokku::Client::ConnectionError, "connection refused" } }

    SyncServerJob.perform_now(@server.id)
    assert_equal "unreachable", @server.reload.status
  end

  test "syncs domains for existing apps" do
    Dokku::Apps.class_eval { define_method(:list) { [ "my-app-one" ] } }
    Dokku::Domains.class_eval { define_method(:list) { |_name| [ "my-app-one.example.com" ] } }

    SyncServerJob.perform_now(@server.id)

    app = @server.app_records.find_by(name: "my-app-one")
    assert app.domains.exists?(hostname: "my-app-one.example.com")
  end

  test "removes stale domains no longer on remote" do
    app = @server.app_records.find_by(name: "my-app-one")
    app.domains.create!(hostname: "stale.example.com")

    Dokku::Apps.class_eval { define_method(:list) { [ "my-app-one" ] } }
    # Remote returns no domains for this app
    Dokku::Domains.class_eval { define_method(:list) { |_name| [] } }

    SyncServerJob.perform_now(@server.id)

    assert_not app.domains.exists?(hostname: "stale.example.com")
  end

  test "syncs new database services from remote" do
    Dokku::Apps.class_eval { define_method(:list) { [ "my-app-one" ] } }
    # Return existing fixture db + a new one so count increases by exactly 1
    Dokku::Databases.class_eval do
      define_method(:list) do |service_type|
        service_type == "postgres" ? [ "pg-main", "mydb-new" ] : []
      end
    end

    assert_difference -> { @server.database_services.count }, 1 do
      SyncServerJob.perform_now(@server.id)
    end

    assert @server.database_services.exists?(name: "mydb-new", service_type: "postgres")
  end

  test "updates synced_at on all app records" do
    Dokku::Apps.class_eval { define_method(:list) { [ "my-app-one" ] } }

    before = 1.hour.ago
    @server.app_records.update_all(synced_at: before)

    SyncServerJob.perform_now(@server.id)

    @server.app_records.reload.each do |app|
      assert app.synced_at > before, "Expected synced_at to be updated for #{app.name}"
    end
  end
end
