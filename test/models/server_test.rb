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

  # --- Platform-owned BackupDestination ---

  ENV_VARS_FOR_BACKUP = %w[
    WOKKU_TENANT_BACKUP_S3_BUCKET
    WOKKU_TENANT_BACKUP_S3_ENDPOINT
    WOKKU_TENANT_BACKUP_S3_ACCESS_KEY_ID
    WOKKU_TENANT_BACKUP_S3_SECRET_ACCESS_KEY
  ].freeze

  def with_backup_env(values)
    original = ENV_VARS_FOR_BACKUP.to_h { |k| [ k, ENV[k] ] }
    values.each { |k, v| ENV[k] = v }
    yield
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  test "ensure_platform_backup_destination creates a destination when env is set" do
    with_backup_env(
      "WOKKU_TENANT_BACKUP_S3_BUCKET"        => "wokku-dataplane",
      "WOKKU_TENANT_BACKUP_S3_ENDPOINT"      => "https://example.r2.cloudflarestorage.com",
      "WOKKU_TENANT_BACKUP_S3_ACCESS_KEY_ID" => "akid",
      "WOKKU_TENANT_BACKUP_S3_SECRET_ACCESS_KEY" => "secret"
    ) do
      server = Server.create!(name: "plat-backup-test", host: "10.0.0.99", team: @team)
      assert server.backup_destination.present?, "expected backup_destination to be auto-created"
      dest = server.backup_destination
      assert_equal "wokku-dataplane", dest.bucket
      assert_equal "dbs/plat-backup-test", dest.path_prefix
      assert_equal "r2", dest.provider
      assert dest.enabled?
    end
  end

  test "ensure_platform_backup_destination no-ops when env is unset" do
    with_backup_env(ENV_VARS_FOR_BACKUP.to_h { |k| [ k, nil ] }) do
      server = Server.create!(name: "no-env-test", host: "10.0.0.88", team: @team)
      assert_nil server.backup_destination
    end
  end
end
