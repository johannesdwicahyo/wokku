require "test_helper"

class TeamTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email: "team-owner@example.com", password: "password123456")
  end

  test "valid team with name and owner" do
    team = Team.new(name: "my-team", owner: @owner)
    assert team.valid?
  end

  test "requires name" do
    team = Team.new(owner: @owner)
    assert_not team.valid?
    assert_includes team.errors[:name], "can't be blank"
  end

  test "name must be unique" do
    Team.create!(name: "unique-team", owner: @owner)
    duplicate = Team.new(name: "unique-team", owner: @owner)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "requires owner" do
    team = Team.new(name: "orphan-team")
    assert_not team.valid?
    assert_includes team.errors[:owner], "must exist"
  end
end
