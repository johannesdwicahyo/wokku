require "test_helper"

class DatabaseServicePolicyTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email: "ds-owner@example.com", password: "password123456")
    @team = Team.create!(name: "DS Team", owner: @owner)
    TeamMembership.create!(user: @owner, team: @team, role: :admin)

    # Server is platform infrastructure (no team).
    @server = Server.create!(name: "ds-server", host: "10.0.0.2")
    @app = AppRecord.create!(name: "ds-app", server: @server, team: @team, creator: @owner)
    @ds = DatabaseService.create!(name: "ds-redis", server: @server, service_type: "redis", status: :running)
    AppDatabase.create!(app_record: @app, database_service: @ds, alias_name: "ds-redis")

    @member = User.create!(email: "ds-member@example.com", password: "password123456")
    TeamMembership.create!(user: @member, team: @team, role: :member)

    @outsider = User.create!(email: "ds-outsider@example.com", password: "password123456")
    Team.create!(name: "Outsider", owner: @outsider).team_memberships.create!(user: @outsider, role: :admin)

    @sysadmin = users(:admin)
  end

  test "scope returns services linked to user's team apps" do
    visible = DatabaseServicePolicy::Scope.new(@member, DatabaseService).resolve
    assert_includes visible.to_a, @ds
  end

  test "scope excludes services not linked to user's team" do
    visible = DatabaseServicePolicy::Scope.new(@outsider, DatabaseService).resolve
    refute_includes visible.to_a, @ds
  end

  test "scope returns everything for system admin" do
    visible = DatabaseServicePolicy::Scope.new(@sysadmin, DatabaseService).resolve
    assert_includes visible.to_a, @ds
  end

  test "show? is true for team member" do
    assert DatabaseServicePolicy.new(@member, @ds).show?
  end

  test "show? is false for outsider" do
    refute DatabaseServicePolicy.new(@outsider, @ds).show?
  end

  test "show? is true for system admin" do
    assert DatabaseServicePolicy.new(@sysadmin, @ds).show?
  end

  test "destroy? is true for team admin via linked app" do
    assert DatabaseServicePolicy.new(@owner, @ds).destroy?
  end

  test "destroy? is false for plain team member" do
    refute DatabaseServicePolicy.new(@member, @ds).destroy?
  end

  test "destroy? is true for system admin even without team" do
    assert DatabaseServicePolicy.new(@sysadmin, @ds).destroy?
  end
end
