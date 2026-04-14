module PricingHelper
  IDR_PER_USD = 15_000

  def format_price(usd_amount, currency = nil)
    currency ||= @currency || "usd"
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
    currency ||= @currency || "usd"
    currency == "idr" ? "/bln" : "/mo"
  end

  def hourly_price_label(currency = nil)
    currency ||= @currency || "usd"
    currency == "idr" ? "/jam" : "/hour"
  end

  def format_hourly_price(usd_cents_per_hour, currency = nil)
    currency ||= @currency || "usd"
    usd = usd_cents_per_hour / 100.0

    if currency == "idr"
      idr = (usd * IDR_PER_USD).round
      "Rp #{number_with_delimiter(idr, delimiter: '.')}"
    else
      "$#{format('%.3f', usd)}"
    end
  end
end
