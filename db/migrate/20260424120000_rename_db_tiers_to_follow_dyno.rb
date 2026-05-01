class RenameDbTiersToFollowDyno < ActiveRecord::Migration[8.1]
  # Renames database tier names to mirror dyno tier naming:
  #   mini     → basic
  #   basic    → standard
  #   standard → performance
  # Plus new IDR-aligned prices (15k/30k/90k/mo at 1 USD = 15k IDR):
  #   basic       = $1/mo (was $0)
  #   standard    = $2/mo (was $1)
  #   performance = $6/mo (was $4)
  # Storage/connections stay mapped to the same underlying tier (new "basic" keeps
  # 1GB/20 conn that old "mini" had, etc.) so existing databases don't silently
  # get larger.
  def up
    # Reverse order so we don't collide on the (name, service_type) unique index.
    rename_tier("standard", "performance")
    rename_tier("basic", "standard")
    rename_tier("mini", "basic")

    # New prices
    reprice("basic",       0.137)  # 15k IDR/mo
    reprice("standard",    0.274)  # 30k IDR/mo
    reprice("performance", 0.8219) # 90k IDR/mo

    # Add a fresh "performance" tier for DB types that didn't have a standard
    # (they'll still get the rename, but any gaps are filled here).
    # No-op for postgres/mysql/mongodb since standard already renamed to performance.
  end

  def down
    # Reverse: performance → standard → basic → mini. Order forward this time.
    rename_tier("standard",    "basic")
    rename_tier("performance", "standard")
    rename_tier("basic",       "mini")

    reprice("basic",    0.0)
    reprice("standard", 0.137)
    # performance no longer exists after down; don't reprice
  end

  DB_TYPES = %w[postgres mysql mongodb].freeze

  private

  def rename_tier(from, to)
    types_sql = DB_TYPES.map { |t| quote(t) }.join(", ")
    # Update DatabaseService.tier_name refs (scoped to DB service types)
    execute("UPDATE database_services SET tier_name = #{quote(to)} WHERE tier_name = #{quote(from)} AND service_type IN (#{types_sql})")
    # Update ServiceTier rows (scoped — leave tiers for other types like minio alone)
    execute("UPDATE service_tiers SET name = #{quote(to)} WHERE name = #{quote(from)} AND service_type IN (#{types_sql})")
  end

  def reprice(tier_name, cents_per_hour)
    execute("UPDATE service_tiers SET price_cents_per_hour = #{cents_per_hour.to_f} WHERE name = #{quote(tier_name)} AND service_type IN ('postgres', 'mysql', 'mongodb')")
  end

  def quote(str)
    ActiveRecord::Base.connection.quote(str)
  end
end
