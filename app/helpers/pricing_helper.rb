# OSS stub for PricingHelper.
#
# wokku-cloud's PricingHelper carries the marketing pricing-page
# constants (COMPARISON_ROWS, COMPETITORS) + USD/IDR currency formatters
# referenced from dashboard views (profile, dashboard, resources). The
# marketing pieces are wokku.cloud-only; the currency formatters render
# "Free" in OSS since nothing's billed.
#
# Pulls in TemplatePricingHelper so the templates index can use it
# (wokku-cloud injects it via a different include chain).

module PricingHelper
  IDR_PER_USD = 15_000

  def format_usd_for_user(_amount, **_)
    "Free"
  end

  def format_cents_for_user(_cents, **_)
    "Free"
  end

  def format_price(_amount, _currency = nil)
    "Free"
  end

  def price_period(_currency = nil)
    "/mo"
  end

  def hourly_price_label(_currency = nil)
    "/hour"
  end

  def default_public_currency
    "usd"
  end
end
