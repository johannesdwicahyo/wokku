class Plan < ApplicationRecord
  KEYS = %w[free solo pro team].freeze

  has_many :users, dependent: :restrict_with_exception

  validates :key, presence: true, uniqueness: true, inclusion: { in: KEYS }
  validates :name, presence: true, uniqueness: true
  validates :price_usd_cents, :price_idr, :seats_included,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.find_by_key!(key)
    find_by!(key: key.to_s)
  end

  def free?    = key == "free"
  def solo?    = key == "solo"
  def pro?     = key == "pro"
  def team?    = key == "team"

  # Box quotas: { "small" => N, "medium" => N, "large" => N, "xlarge" => N, "sleeping" => N }
  # (renamed from slot_quotas in 1.9 box-rename — keys for size labels stay)
  def quota_for(size)
    box_quotas.fetch(size.to_s, 0).to_i
  end

  # pro_features: ["pr_previews", "transfer_app", "scheduled_tasks"]
  def has_feature?(slug)
    pro_features.include?(slug.to_s)
  end

  def price_usd
    price_usd_cents / 100.0
  end

  # ─────────────────────────────────────────────────────────────────
  # Bundle v2 (founder decision 2026-05-29, see
  # memory/project_bundle_v2_locked_spec.md).
  #
  # Every app box can attach the shared stack at create time:
  # Pg + Redis + Memcached (rabbitmq/meilisearch left the offering
  # 2026-10-05). Per-tenant size
  # caps come from this model. Dedicated Pg/Redis are upgrade slots
  # (per workspace, plan-quota of N, no overage).
  # ─────────────────────────────────────────────────────────────────

  # P2 rider cleanup: the ENGINE owns these product catalogs now
  # (DatabaseService for datastore engines, DynoTier for the box-size map).
  # Aliased here so existing cloud-side Plan::X references keep working.
  SHARED_ENGINES        = DatabaseService::SHARED_ENGINES
  DEDICATED_ENGINES     = DatabaseService::DEDICATED_ENGINES
  SHARED_ENGINES_FREE   = DatabaseService::SHARED_ENGINES_FREE
  BOX_SIZE_TO_DYNO_TIER = DynoTier::BOX_SIZE_TO_DYNO_TIER
  DYNO_TIER_TO_BOX_SIZE = DynoTier::DYNO_TIER_TO_BOX_SIZE

  # Per-engine, per-tenant cap. Routes the lookup to the right column
  # so callers don't have to special-case engine names.
  def shared_tenant_cap(engine)
    case engine.to_s
    when "postgres"    then shared_pg_mb_per_tenant.to_i
    when "redis"       then shared_redis_mb_per_tenant.to_i
    when "memcached"   then shared_memcached_mb_per_tenant.to_i
    else raise ArgumentError, "Unknown shared engine #{engine.inspect}"
    end
  end

  # Whether this plan offers any dedicated upgrade for the given engine.
  # Free returns false on both; paid plans return true on postgres + redis.
  def offers_dedicated?(engine)
    dedicated_slot_cap(engine).positive?
  end

  # Per-engine slot count. Used by quota check at upgrade time.
  def dedicated_slot_cap(engine)
    case engine.to_s
    when "postgres" then dedicated_pg_slots.to_i
    when "mariadb"  then dedicated_pg_slots.to_i
    when "redis"    then dedicated_redis_slots.to_i
    else 0
    end
  end

  # Per-engine dedicated container size (MB).
  def dedicated_size_mb(engine)
    case engine.to_s
    when "postgres" then dedicated_pg_size_mb.to_i
    when "redis"    then dedicated_redis_size_mb.to_i
    else 0
    end
  end

  # Convenience: every plan ships the same 5 shared engines (caps differ
  # but the engine set is identical), so call sites that iterate them
  # all can grab this list without checking per-engine availability.
  def shared_engines
    SHARED_ENGINES
  end

  # Bundle v2 REVISED 2026-05-31: which shared engines can a user pick
  # from at box creation under this plan? Free: Pg+Redis only. All
  # others: all 5. Used by the new-app form addon picker.
  def shared_engines_available
    free? ? SHARED_ENGINES_FREE : SHARED_ENGINES
  end

  # Bundle v2 REVISED 2026-05-31: only Team plan can buy boxes/addons
  # beyond the plan default. `addons_available` is empty on Free/Solo/
  # Pro; populated only on Team (`{ "large" => 1000, "xlarge" => 2000 }`).
  def allows_extras?
    team?
  end

  # Per-size recurring price for a purchased extra box, in the requested
  # currency. Reads the dual-currency addons_available jsonb (seeded).
  # Returns nil when this plan doesn't sell that size.
  def extra_box_price(size, currency: :idr)
    entry = addons_available[size.to_s]
    return nil unless entry.is_a?(Hash)
    currency.to_sym == :usd ? entry["usd_cents"]&.to_i : entry["idr"]&.to_i
  end

  # Sizes this plan can buy as extras. Empty unless the plan allows extras.
  def buyable_box_sizes
    allows_extras? ? addons_available.keys : []
  end
end
