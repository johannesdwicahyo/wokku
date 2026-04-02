require "test_helper"

class AppRecordTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email: "app-owner@example.com", password: "password123456")
    @team = Team.create!(name: "app-team", owner: @owner)
    @server = Server.create!(name: "app-server", host: "10.0.0.1", team: @team)
  end

  # --- Validations ---

  test "valid app record" do
    app = AppRecord.new(name: "my-app", server: @server, team: @team, creator: @owner)
    assert app.valid?
  end

  test "requires name" do
    app = AppRecord.new(server: @server, team: @team, creator: @owner)
    assert_not app.valid?
    assert_includes app.errors[:name], "can't be blank"
  end

  test "name must be lowercase alphanumeric with hyphens" do
    app = AppRecord.new(name: "My_App", server: @server, team: @team, creator: @owner)
    assert_not app.valid?
    assert_includes app.errors[:name], "must be lowercase alphanumeric with hyphens"
  end

  test "name cannot start with a number" do
    app = AppRecord.new(name: "1app", server: @server, team: @team, creator: @owner)
    assert_not app.valid?
  end

  test "name cannot start with a hyphen" do
    app = AppRecord.new(name: "-app", server: @server, team: @team, creator: @owner)
    assert_not app.valid?
  end

  test "valid name with hyphens" do
    app = AppRecord.new(name: "my-cool-app", server: @server, team: @team, creator: @owner)
    assert app.valid?
  end

  test "name unique within server" do
    AppRecord.create!(name: "unique-app", server: @server, team: @team, creator: @owner)
    duplicate = AppRecord.new(name: "unique-app", server: @server, team: @team, creator: @owner)
    assert_not duplicate.valid?
  end

  test "same name allowed on different servers" do
    other_server = Server.create!(name: "other-server", host: "10.0.0.2", team: @team)
    AppRecord.create!(name: "shared-name", server: @server, team: @team, creator: @owner)
    app2 = AppRecord.new(name: "shared-name", server: other_server, team: @team, creator: @owner)
    assert app2.valid?
  end

  # --- Status enum ---

  test "default status is running" do
    app = AppRecord.new(name: "status-app", server: @server, team: @team, creator: @owner)
    assert_equal "running", app.status
  end

  test "status enum includes all expected values" do
    assert_equal({ "running" => 0, "stopped" => 1, "crashed" => 2, "deploying" => 3, "sleeping" => 4 }, AppRecord.statuses)
  end

  test "can set status to stopped" do
    app = AppRecord.create!(name: "stop-app", server: @server, team: @team, creator: @owner)
    app.stopped!
    assert app.stopped?
  end

  # --- Defaults ---

  test "default deploy_branch is main" do
    app = AppRecord.new(name: "branch-app", server: @server, team: @team, creator: @owner)
    assert_equal "main", app.deploy_branch
  end

  # --- Scopes ---

  test "stale scope returns records with old or nil synced_at" do
    fresh = AppRecord.create!(name: "fresh-app", server: @server, team: @team, creator: @owner, synced_at: 1.minute.ago)
    stale = AppRecord.create!(name: "stale-app", server: @server, team: @team, creator: @owner, synced_at: 10.minutes.ago)
    nil_sync = AppRecord.create!(name: "nil-app", server: @server, team: @team, creator: @owner, synced_at: nil)

    stale_apps = AppRecord.stale
    assert_not_includes stale_apps, fresh
    assert_includes stale_apps, stale
    assert_includes stale_apps, nil_sync
  end

  # --- Associations ---

  test "belongs to server" do
    app = AppRecord.create!(name: "assoc-app", server: @server, team: @team, creator: @owner)
    assert_equal @server, app.server
  end

  test "belongs to team" do
    app = AppRecord.create!(name: "team-app", server: @server, team: @team, creator: @owner)
    assert_equal @team, app.team
  end

  test "belongs to creator" do
    app = AppRecord.create!(name: "creator-app", server: @server, team: @team, creator: @owner)
    assert_equal @owner, app.creator
  end

  test "has many releases" do
    assert_respond_to app_records(:one), :releases
  end

  test "has many deploys" do
    assert_respond_to app_records(:one), :deploys
  end

  test "has many domains" do
    assert_respond_to app_records(:one), :domains
  end

  test "has many env_vars" do
    assert_respond_to app_records(:one), :env_vars
  end

  test "has many notifications" do
    assert_respond_to app_records(:one), :notifications
  end
end
