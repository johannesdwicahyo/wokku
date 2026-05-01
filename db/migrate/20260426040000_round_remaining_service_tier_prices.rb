class RoundRemainingServiceTierPrices < ActiveRecord::Migration[8.1]
  # Make every service tier display as a round IDR figure instead of
  # the backfilled hourly × 720 number (e.g. elasticsearch basic was
  # showing Rp 59.100/bln from 0.5479¢/hr × 720). monthly_price_cents
  # is the canonical source; price_cents_per_hour is derived for the
  # billing engine which still bills hourly under the cap-at-720h rule.
  #
  # IDR per USD = 15_000, so $1 = Rp 15k. USD cents column.
  PRICES = {
    "redis"         => { "mini" => 0,   "basic" => 100 },           # 0,  Rp 15k
    "memcached"     => { "mini" => 0,   "basic" => 100 },           # 0,  Rp 15k
    "elasticsearch" => { "basic" => 200, "standard" => 400 },        # 30k, 60k
    "meilisearch"   => { "mini" => 0,   "basic" => 200, "standard" => 400 },  # 0, 30k, 60k
    "rabbitmq"      => { "mini" => 0,   "basic" => 100, "standard" => 200 },
    "nats"          => { "mini" => 0,   "basic" => 100, "standard" => 200 },
    "clickhouse"    => { "basic" => 400, "standard" => 800 }         # 60k, 120k
  }.freeze

  def up
    PRICES.each do |service_type, by_name|
      by_name.each do |name, cents|
        execute(
          ActiveRecord::Base.sanitize_sql_array([
            "UPDATE service_tiers SET monthly_price_cents = ?, price_cents_per_hour = ?, updated_at = NOW() WHERE name = ? AND service_type = ?",
            cents, cents.to_f / 720.0, name, service_type
          ])
        )
      end
    end
  end

  def down
    # No-op
  end
end
