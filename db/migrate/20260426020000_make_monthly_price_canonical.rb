class MakeMonthlyPriceCanonical < ActiveRecord::Migration[8.1]
  # Pricing model is monthly = source of truth, hourly = monthly / 720,
  # daily = monthly / 30, with the daily-deduction job already capping at
  # 720h/month. Prior schema only stored price_cents_per_hour, which made
  # round IDR monthly figures impossible (0.137¢/hr × 720 = ~Rp 14,796 →
  # displayed as Rp 14,850 instead of an exact Rp 15,000).
  #
  # New canonical column: monthly_price_cents (USD cents). hourly is now
  # derived from it. Existing rows are backfilled from the previous
  # hourly × 720 product to preserve current advertised prices, then the
  # DB tier rows are rounded to the intended IDR-aligned monthlies so the
  # picker reads as round numbers.
  def up
    add_column :service_tiers, :monthly_price_cents, :integer, default: 0, null: false unless column_exists?(:service_tiers, :monthly_price_cents)
    add_column :dyno_tiers,    :monthly_price_cents, :integer, default: 0, null: false unless column_exists?(:dyno_tiers, :monthly_price_cents)

    execute "UPDATE service_tiers SET monthly_price_cents = ROUND(price_cents_per_hour * 720)::int"
    execute "UPDATE dyno_tiers    SET monthly_price_cents = ROUND(price_cents_per_hour * 720)::int"

    # Round DB tier monthlies to clean IDR figures.
    # IDR_PER_USD = 15_000 → $1 = Rp 15,000.
    {
      "basic"       => 100,  # Rp 15,000
      "standard"    => 200,  # Rp 30,000
      "performance" => 600   # Rp 90,000
    }.each do |name, cents|
      %w[postgres mysql mongodb].each do |db_type|
        execute(
          ActiveRecord::Base.sanitize_sql_array([
            "UPDATE service_tiers SET monthly_price_cents = ?, price_cents_per_hour = ?, updated_at = NOW() WHERE name = ? AND service_type = ?",
            cents, cents.to_f / 720.0, name, db_type
          ])
        )
      end
    end

    # Round dyno tier monthlies to clean IDR figures so app cost displays
    # also read as round numbers (matches the seed's intent of $1.50/$4/$8/$15).
    {
      "free"           => 0,
      "basic"          => 150,
      "standard"       => 400,
      "performance"    => 800,
      "performance-2x" => 1500
    }.each do |name, cents|
      execute(
        ActiveRecord::Base.sanitize_sql_array([
          "UPDATE dyno_tiers SET monthly_price_cents = ?, price_cents_per_hour = ?, updated_at = NOW() WHERE name = ?",
          cents, cents.to_f / 720.0, name
        ])
      )
    end
  end

  def down
    remove_column :service_tiers, :monthly_price_cents
    remove_column :dyno_tiers, :monthly_price_cents
  end
end
