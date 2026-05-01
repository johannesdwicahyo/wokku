require "test_helper"

class BillingCalculatorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @period_start = Time.parse("2026-03-01 00:00 UTC")
    @period_end = Time.parse("2026-03-31 23:59:59 UTC")
  end

  test "calculates total cost for user in period" do
    ResourceUsage.create!(
      user: @user,
      resource_type: "container",
      resource_id_ref: "AppRecord:1",
      tier_name: "basic",
      price_cents_per_hour: 0.4,
      started_at: @period_start,
      stopped_at: @period_start + 10.days
    )

    calc = BillingCalculator.new(@user, @period_start, @period_end)
    result = calc.calculate

    assert_equal 1, result[:line_items].size
    item = result[:line_items].first
    assert_equal "container", item[:resource_type]
    assert_equal "basic", item[:tier_name]
    assert_in_delta 240.0, item[:hours], 0.1
    assert_in_delta 96.0, item[:cost_cents], 1.0
    assert_in_delta result[:total_cents], 96.0, 1.0
  end

  test "skips free resources" do
    ResourceUsage.create!(
      user: @user,
      resource_type: "container",
      resource_id_ref: "AppRecord:1",
      tier_name: "eco",
      price_cents_per_hour: 0,
      started_at: @period_start,
      stopped_at: nil
    )

    calc = BillingCalculator.new(@user, @period_start, @period_end)
    result = calc.calculate

    assert_equal 0, result[:total_cents]
  end
end
