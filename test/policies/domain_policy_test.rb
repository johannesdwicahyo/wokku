require "test_helper"

class DomainPolicyTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email: "domain-policy-owner@example.com", password: "password123456")
    @team = Team.create!(name: "Domain Policy Team", owner: @owner)
    TeamMembership.create!(user: @owner, team: @team, role: :admin)
    @server = Server.create!(name: "dp-server", host: "10.0.0.1", team: @team)
    @app = AppRecord.create!(name: "dp-app", server: @server, team: @team, creator: @owner)
    @domain = @app.domains.create!(hostname: "dp.example.com", ssl_enabled: false)

    @member = User.create!(email: "domain-policy-member@example.com", password: "password123456")
    TeamMembership.create!(user: @member, team: @team, role: :member)

    @outsider = User.create!(email: "domain-policy-outsider@example.com", password: "password123456")
  end

  # --- index? ---

  test "index? is always true for any user" do
    assert DomainPolicy.new(@owner, @domain).index?
    assert DomainPolicy.new(@member, @domain).index?
    assert DomainPolicy.new(@outsider, @domain).index?
  end

  # --- create? ---

  test "create? is true for team admin" do
    assert DomainPolicy.new(@owner, @domain).create?
  end

  test "create? is true for team member" do
    assert DomainPolicy.new(@member, @domain).create?
  end

  test "create? is false for outsider" do
    assert_not DomainPolicy.new(@outsider, @domain).create?
  end

  # --- destroy? ---

  test "destroy? is true for team admin" do
    assert DomainPolicy.new(@owner, @domain).destroy?
  end

  test "destroy? is true for team member" do
    assert DomainPolicy.new(@member, @domain).destroy?
  end

  test "destroy? is false for outsider" do
    assert_not DomainPolicy.new(@outsider, @domain).destroy?
  end

  # --- ssl? ---

  test "ssl? is true for team admin" do
    assert DomainPolicy.new(@owner, @domain).ssl?
  end

  test "ssl? is true for team member" do
    assert DomainPolicy.new(@member, @domain).ssl?
  end

  test "ssl? is false for outsider" do
    assert_not DomainPolicy.new(@outsider, @domain).ssl?
  end

  # --- Scope ---

  test "Scope resolves domains for user's team" do
    other_team = Team.create!(name: "Other DP Team", owner: @outsider)
    TeamMembership.create!(user: @outsider, team: other_team, role: :admin)
    other_server = Server.create!(name: "other-dp-srv", host: "9.9.9.9", team: other_team)
    other_app = AppRecord.create!(name: "other-dp-app", server: other_server, team: other_team, creator: @outsider)
    other_domain = other_app.domains.create!(hostname: "other-dp.example.com", ssl_enabled: false)

    scope = DomainPolicy::Scope.new(@owner, Domain.all).resolve
    assert_includes scope, @domain
    assert_not_includes scope, other_domain
  end
end
