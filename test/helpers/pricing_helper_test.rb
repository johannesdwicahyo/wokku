require "test_helper"

class PricingHelperTest < ActionView::TestCase
  include PricingHelper

  test "format_price in USD with whole number" do
    assert_equal "$4", format_price(4.0, "usd")
  end

  test "format_price in USD with cents" do
    assert_equal "$1.50", format_price(1.5, "usd")
  end

  test "format_price in USD zero" do
    assert_equal "$0", format_price(0, "usd")
  end

  test "format_price in IDR converts at 15000 rate" do
    assert_equal "Rp 22.500", format_price(1.5, "idr")
  end

  test "format_price in IDR whole dollar" do
    assert_equal "Rp 60.000", format_price(4.0, "idr")
  end

  test "format_price in IDR zero" do
    assert_equal "Rp 0", format_price(0, "idr")
  end

  test "format_price in IDR large amount" do
    assert_equal "Rp 225.000", format_price(15.0, "idr")
  end

  test "format_price defaults to usd" do
    assert_equal "$4", format_price(4.0)
  end

  test "price_period for usd" do
    assert_equal "/mo", price_period("usd")
  end

  test "price_period for idr" do
    assert_equal "/bln", price_period("idr")
  end

  test "hourly_price_label for usd" do
    assert_equal "/hour", hourly_price_label("usd")
  end

  test "hourly_price_label for idr" do
    assert_equal "/jam", hourly_price_label("idr")
  end
end
