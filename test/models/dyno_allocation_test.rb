require "test_helper"

class DynoAllocationTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email: "dyno-owner@example.com", password: "password123456")
    @team = Team.create!(name: "dyno-team", owner: @owner)
    @server = Server.create!(name: "dyno-server", host: "10.0.0.50", team: @team)
    @app = AppRecord.create!(name: "dyno-app", server: @server, team: @team, creator: @owner)
    @tier = dyno_tiers(:basic)
  end

  test "valid allocation" do
    alloc = DynoAllocation.new(app_record: @app, dyno_tier: @tier, process_type: "web", count: 1)
    assert alloc.valid?
  end

  test "requires process_type" do
    alloc = DynoAllocation.new(app_record: @app, dyno_tier: @tier, count: 1)
    assert_not alloc.valid?
    assert_includes alloc.errors[:process_type], "can't be blank"
  end

  test "process_type unique per app" do
    DynoAllocation.create!(app_record: @app, dyno_tier: @tier, process_type: "web", count: 1)
    dup = DynoAllocation.new(app_record: @app, dyno_tier: @tier, process_type: "web", count: 2)
    assert_not dup.valid?
  end

  test "count must be non-negative" do
    alloc = DynoAllocation.new(app_record: @app, dyno_tier: @tier, process_type: "web", count: -1)
    assert_not alloc.valid?
  end

  test "count defaults to 1" do
    alloc = DynoAllocation.new(app_record: @app, dyno_tier: @tier, process_type: "web")
    assert_equal 1, alloc.count
  end

  test "monthly_cost_cents calculates correctly" do
    alloc = DynoAllocation.new(app_record: @app, dyno_tier: @tier, process_type: "web", count: 3)
    assert_equal 1500, alloc.monthly_cost_cents
  end

  test "app_record has_many dyno_allocations" do
    alloc = DynoAllocation.create!(app_record: @app, dyno_tier: @tier, process_type: "web", count: 1)
    assert_includes @app.dyno_allocations, alloc
  end
end
