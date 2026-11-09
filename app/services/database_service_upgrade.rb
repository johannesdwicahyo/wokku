class DatabaseServiceUpgrade
  # Bundle v2 REVISED 2026-05-31 (see memory/project_bundle_v2_locked_spec.md):
  # - Database engines: postgres, mysql, mariadb, mongo. All 4 share one quota pool
  #   (plan.dedicated_pg_slots) since the locked spec describes a single
  #   "dedicated DB" slot per box, regardless of engine.
  # - Redis is its own engine + own quota pool (plan.dedicated_redis_slots).
  # - postgres/redis must upgrade FROM a shared tenant (data migrated).
  #   mariadb migrates its shared tenant when the app has one (shared
  #   MariaDB, 2026-10-06), else fresh-creates. MySQL/Mongo: fresh only.
  # - Size of the dedicated container follows the BOX size, not a plan-
  #   fixed cap. See BOX_SIZE_TO_TIER.

  DB_ENGINES_POOL    = %w[postgres mysql mariadb mongodb].freeze
  REDIS_ENGINE       = "redis".freeze
  ENGINES_WITH_SHARED_SOURCE = %w[postgres redis].freeze
  ENGINES_WITH_OPTIONAL_SHARED_SOURCE = %w[mariadb].freeze

  # Map box size → DynoTier/ServiceTier name. Mirrors the seed names in
  # db/seeds.rb. Used to derive the dedicated container's resource specs.
  # Falls through to "basic" for nil / unknown sizes (defensive default
  # during the transition; once box_size is populated for all rows this
  # becomes strict).
  BOX_SIZE_TO_TIER = {
    "sleeping" => "basic",
    "small"    => "basic",
    "medium"   => "standard",
    "large"    => "performance",
    "xlarge"   => "performance"
  }.freeze

  def self.call(app:, user:, engine: "postgres")
    new(app: app, user: user, engine: engine).call
  end

  def initialize(app:, user:, engine: "postgres")
    @app    = app
    @user   = user
    @engine = engine.to_s
  end

  def call
    raise UpgradeError::PlanNoSlots.new(engine: @engine) unless Addons::SharedProvisioner.feature_enabled?

    plan = @user.current_plan
    # Per-resource billing has no plan slots: the account limit
    # (check_new_shape below) gates dedicated instead.
    plan_caps = !Wokku.config.resource_builder?
    raise UpgradeError::PlanNoSlots.new(engine: @engine) if plan_caps && slots_cap(plan).zero?

    # postgres/redis require a shared tenant to upgrade FROM; mariadb uses
    # one if present (before 2026-10-13 it was ignored → the app landed on an
    # EMPTY dedicated DB). MySQL/Mongo are fresh-create — nothing to check.
    shared = nil
    if (ENGINES_WITH_SHARED_SOURCE + ENGINES_WITH_OPTIONAL_SHARED_SOURCE).include?(@engine)
      shared = @app.database_services.where(service_type: @engine, shared: true).first
      raise UpgradeError::NoSharedTenant.new(engine: @engine) if shared.nil? && ENGINES_WITH_SHARED_SOURCE.include?(@engine)
    end

    User.transaction do
      @user.lock!

      if plan_caps
        used = DatabaseService.dedicated.where(service_type: slot_pool_types, creator_id: @user.id).count
        raise UpgradeError::NoFreeSlots.new(engine: @engine) if used >= slots_cap(plan)
      end

      # Size-cap check is shared-engine only (mysql/mongo have nothing to
      # check — no shared data exists to oversize the dedicated cap).
      if shared && plan_caps
        size_mb = (shared.live_db_bytes.to_i.to_f / 1.megabyte).ceil
        if size_mb > size_mb_cap(plan)
          next_plan_name = plan.key == "solo" ? "Pro" : "Team"
          raise UpgradeError::ExceedsDedicatedCap.new(
            size_mb: size_mb, cap_mb: size_mb_cap(plan),
            plan: plan.name, next_plan: next_plan_name, engine: @engine
          )
        end
      end

      attrs = {
        server: @app.server,
        service_type: @engine,
        name: "#{@app.name}-#{@engine}-dedicated",
        tier_name: tier_name_for_box,
        shared: false,
        status: :upgrading_provisioning,
        creator: @user,
        upgrade_source_id: shared&.id
      }
      # Builder mode: born shaped (a tier-only row bills Rp0), gated by the
      # builder's enforcer + capacity check before anything is created.
      if (shape = Resources::ApplyChange.service_shape_for_tier(@engine, attrs[:tier_name]))
        check = Resources::ApplyChange.check_new_shape(team: @app.team, server: @app.server, shape: shape)
        raise UpgradeError::OverLimit, check.error unless check.ok
        attrs.merge!(cpu: shape.cpu, memory_mb: shape.memory_mb, disk_gb: shape.disk_gb)
      end
      dedicated = DatabaseService.create!(attrs)

      job_class(shared).perform_later(dedicated.id)
      dedicated
    end
  end

  private

  # Database engines share a single dedicated-DB quota pool per plan.
  # Redis has its own. Returns the list of service_types to count when
  # checking slot usage.
  def slot_pool_types
    REDIS_ENGINE == @engine ? [ REDIS_ENGINE ] : DB_ENGINES_POOL
  end

  def slots_cap(plan)
    case @engine
    when REDIS_ENGINE then plan.dedicated_redis_slots.to_i
    else                   plan.dedicated_pg_slots.to_i
    end
  end

  def size_mb_cap(plan)
    case @engine
    when REDIS_ENGINE then plan.dedicated_redis_size_mb.to_i
    else                   plan.dedicated_pg_size_mb.to_i
    end
  end

  def job_class(shared)
    case @engine
    when "postgres"    then UpgradeSharedPgToDedicatedJob
    when "redis"       then UpgradeSharedRedisToDedicatedJob
    when "mariadb"     then shared ? UpgradeSharedPgToDedicatedJob : CreateDedicatedDatabaseJob
    when "mysql", "mongodb" then CreateDedicatedDatabaseJob
    end
  end

  # Bundle v2 REVISED 2026-05-31: dedicated size follows box size, not
  # plan-fixed cap. Falls through to "basic" defensively for legacy rows
  # without box_size populated yet.
  def tier_name_for_box
    BOX_SIZE_TO_TIER.fetch(@app.box_size.to_s, "basic")
  end
end
