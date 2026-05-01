require "test_helper"

class TeamMembershipTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email: "membership-owner@example.com", password: "password123456")
    @team = Team.create!(name: "membership-team", owner: @owner)
    @user = User.create!(email: "membership-user@example.com", password: "password123456")
  end

  test "valid membership" do
    membership = TeamMembership.new(user: @user, team: @team, role: :member)
    assert membership.valid?
  end

  test "default role is viewer" do
    membership = TeamMembership.new(user: @user, team: @team)
    assert_equal "viewer", membership.role
  end

  test "user can only belong to a team once" do
    TeamMembership.create!(user: @user, team: @team, role: :member)
    duplicate = TeamMembership.new(user: @user, team: @team, role: :admin)
    assert_not duplicate.valid?
  end

  test "role enum values" do
    assert_equal 0, TeamMembership.roles[:viewer]
    assert_equal 1, TeamMembership.roles[:member]
    assert_equal 2, TeamMembership.roles[:admin]
  end
end
