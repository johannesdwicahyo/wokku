module PricingHelper
  # Mirror Billing::Money's constant so the helper module has the same
  # rate as the billing service. Single source of truth lives there;
  # this is just a re-export for view-layer access without a require.
  IDR_PER_USD = Billing::Money::IDR_PER_USD

  # Primary entry point for rendering a USD-denominated amount as the
  # right currency for the current user + launch mode. Centralises the
  # IDR-only override so billing views don't have to sprinkle checks.
  def format_usd_for_user(usd_amount, override: nil)
    resolved = override || (Wokku::LaunchMode.idr_only? ? "idr" : (@currency || "usd"))
    format_price(usd_amount, resolved)
  end

  # Same, but input is cents (schema-stored Invoice#amount_cents,
  # Transaction#amount when currency=usd, etc.).
  def format_cents_for_user(cents, override: nil)
    format_usd_for_user((cents || 0) / 100.0, override: override)
  end

  # Under launch mode every public page (landing, deploy, pricing,
  # docs) should default to IDR when no per-user / per-view override
  # is set. Kept as a shim rather than hardcoding per helper so flipping
  # the flag off re-exposes USD everywhere in one line.
  def default_public_currency
    Wokku::LaunchMode.idr_only? ? "idr" : "usd"
  end

  def format_price(usd_amount, currency = nil)
    currency ||= @currency || default_public_currency
    usd_amount = usd_amount.to_f

    if currency == "idr"
      idr = (usd_amount * IDR_PER_USD).round
      if idr == 0
        "Rp 0"
      else
        "Rp #{number_with_delimiter(idr, delimiter: '.')}"
      end
    else
      if usd_amount == 0
        "$0"
      elsif usd_amount == usd_amount.to_i
        "$#{usd_amount.to_i}"
      else
        "$#{format('%.2f', usd_amount)}"
      end
    end
  end

  def price_period(currency = nil)
    currency ||= @currency || default_public_currency
    currency == "idr" ? "/bln" : "/mo"
  end

  def hourly_price_label(currency = nil)
    currency ||= @currency || default_public_currency
    currency == "idr" ? "/jam" : "/hour"
  end

  # Daily price derived from the monthly cap as monthly ÷ 30. We bill
  # hourly internally but debit the deposit once per day, so "per day"
  # matches what shows up in the user's balance; "per hour" is too
  # granular for IDR (Rp 31,25 looks odd in a currency that's almost
  # never written with decimals in everyday life).
  def format_daily_from_monthly(usd_monthly, currency = nil)
    daily_usd = usd_monthly.to_f / 30.0
    currency ||= @currency || default_public_currency
    if currency == "idr" && daily_usd > 0
      # Round to nearest rupiah since /30 of a clean monthly Rp amount
      # comes out whole (Rp 22.500 / 30 = 750, Rp 60.000 / 30 = 2.000, etc.).
      idr = (daily_usd * IDR_PER_USD).round
      "Rp #{number_with_delimiter(idr, delimiter: '.')}"
    else
      format_price(daily_usd, currency)
    end
  end

  def daily_price_label(currency = nil)
    currency ||= @currency || default_public_currency
    currency == "idr" ? "/hari" : "/day"
  end

  # Pricing + docs render "Shared vCPU" for any tier under 1.0 vCPU.
  # Exposing fractional cores to end users is misleading since actual
  # burst behaviour depends on neighbour load, not the exact share.
  # Performance (1.0) and Performance-2x (2.0) keep their numeric
  # labels because they have dedicated cores.
  def vcpu_display(value)
    return "Shared" if value.to_f < 1.0
    value.to_s.sub(/\.0+\z/, "")
  end

  # Per-app monthly share for an addon. When an addon is linked to multiple
  # apps the cost is one underlying resource — pro-rate across the linked
  # apps so two app pages don't each show the full price (which would
  # imply double-billing). Shared-tier addons (free shared Postgres) and
  # zero-rate tiers always return 0.
  #
  # Returns [share_dollars, link_count]. link_count of 0 means orphan; we
  # show full cost in that case (creator is the sole bill payer).
  def addon_monthly_share(addon)
    return [ 0.0, 0 ] if addon.shared?
    monthly = addon.service_tier&.monthly_price_dollars.to_f
    return [ 0.0, 0 ] if monthly.zero?
    count = addon.app_records.size
    return [ monthly, 0 ] if count.zero?
    [ monthly / count, count ]
  end

  def format_hourly_price(usd_cents_per_hour, currency = nil)
    currency ||= @currency || default_public_currency
    usd = usd_cents_per_hour / 100.0

    if currency == "idr"
      idr = (usd * IDR_PER_USD).round
      "Rp #{number_with_delimiter(idr, delimiter: '.')}"
    else
      "$#{format('%.3f', usd)}"
    end
  end
end
