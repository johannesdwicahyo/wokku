require "test_helper"

class PlanTest < ActiveSupport::TestCase
  test "valid plan" do
    plan = Plan.new(name: "starter", max_apps: 3, max_dynos: 5, max_databases: 1, price_cents_per_month: 500)
    assert plan.valid?
  end

  test "requires name" do
    plan = Plan.new(max_apps: 3, max_dynos: 5, max_databases: 1, price_cents_per_month: 500)
    assert_not plan.valid?
    assert_includes plan.errors[:name], "can't be blank"
  end

  test "name must be unique" do
    Plan.create!(name: "unique-plan", max_apps: 3, max_dynos: 5, max_databases: 1, price_cents_per_month: 500)
    dup = Plan.new(name: "unique-plan", max_apps: 3, max_dynos: 5, max_databases: 1, price_cents_per_month: 500)
    assert_not dup.valid?
  end

  test "requires numeric fields" do
    plan = Plan.new(name: "test")
    assert_not plan.valid?
    assert_includes plan.errors[:max_apps], "can't be blank"
    assert_includes plan.errors[:max_dynos], "can't be blank"
    assert_includes plan.errors[:max_databases], "can't be blank"
    assert_includes plan.errors[:price_cents_per_month], "can't be blank"
  end

  test "numeric fields must be non-negative" do
    plan = Plan.new(name: "test", max_apps: -1, max_dynos: 5, max_databases: 1, price_cents_per_month: 500)
    assert_not plan.valid?
    assert_includes plan.errors[:max_apps], "must be greater than or equal to 0"
  end

  test "free? returns true for zero price" do
    plan = plans(:free)
    assert plan.free?
  end

  test "free? returns false for non-zero price" do
    plan = plans(:hobby)
    assert_not plan.free?
  end
end
