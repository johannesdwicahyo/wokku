require "test_helper"

class DynoTierTest < ActiveSupport::TestCase
  test "valid dyno tier" do
    tier = DynoTier.new(name: "test-tier", memory_mb: 512, cpu_shares: 50, price_cents_per_month: 500)
    assert tier.valid?
  end

  test "requires name" do
    tier = DynoTier.new(memory_mb: 512, cpu_shares: 50, price_cents_per_month: 500)
    assert_not tier.valid?
    assert_includes tier.errors[:name], "can't be blank"
  end

  test "name must be unique" do
    DynoTier.create!(name: "unique-tier", memory_mb: 256, cpu_shares: 25, price_cents_per_month: 0)
    tier = DynoTier.new(name: "unique-tier", memory_mb: 512, cpu_shares: 50, price_cents_per_month: 500)
    assert_not tier.valid?
  end

  test "requires numeric fields" do
    tier = DynoTier.new(name: "bad-tier")
    assert_not tier.valid?
    assert_includes tier.errors[:memory_mb], "can't be blank"
    assert_includes tier.errors[:cpu_shares], "can't be blank"
    assert_includes tier.errors[:price_cents_per_month], "can't be blank"
  end

  test "numeric fields must be non-negative integers" do
    tier = DynoTier.new(name: "neg-tier", memory_mb: -1, cpu_shares: -1, price_cents_per_month: -1)
    assert_not tier.valid?
  end

  test "paid scope excludes sleeping tiers" do
    eco = dyno_tiers(:eco)
    basic = dyno_tiers(:basic)
    paid = DynoTier.paid
    assert_not_includes paid, eco
    assert_includes paid, basic
  end

  test "price_per_month converts cents to dollars" do
    tier = DynoTier.new(price_cents_per_month: 1200)
    assert_equal 12.0, tier.price_per_month
  end

  test "sleeps defaults to false" do
    tier = DynoTier.new(name: "default-sleep", memory_mb: 256, cpu_shares: 25, price_cents_per_month: 0)
    assert_equal false, tier.sleeps
  end
end
