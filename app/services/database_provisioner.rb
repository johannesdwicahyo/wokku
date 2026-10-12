# Central provisioning path for database add-ons. Branches between dedicated
# (wokkud service.create) and shared (tenant.provision on the shared-postgres
# parent) so every caller — controllers, API, template deployer — uses one
# code path.
class DatabaseProvisioner
  class Error < StandardError; end

  SHARED_TIER = "shared_free".freeze
  DEFAULT_TIER = "basic".freeze
  # Name of the shared-postgres parent container — the host every shared
  # tenant DSN points at (resolves on the wokku-services overlay).
  SHARED_PG_NETWORK = "dokku-shared-postgres".freeze
  # The shared-MariaDB parent container (wokkud births it on first ensure).
  SHARED_MARIADB_PARENT = "dokku-shared-mariadb".freeze
  # SQL engines with a shared (tenant-in-a-parent) path, engine => parent
  # container/row name.
  SHARED_PARENTS = { "postgres" => SHARED_PG_NETWORK, "mariadb" => SHARED_MARIADB_PARENT }.freeze
  # Free-tier quota for new shared tenants when the creator has no plan
  # resolution (was the dokku-shared-postgres plugin default).
  DEFAULT_SHARED_STORAGE_MB = 150
  # B4 gate 3: wokkud-managed dedicated services live on one user-defined
  # bridge network so their container-name DSN hosts resolve via Docker
  # DNS (the default bridge has none). Same flat reachability as today's
  # bridge — per-service isolation arrives with B5/Swarm overlays.
  DEDICATED_NETWORK = "wokku-services".freeze

  # Phase B4: per-engine default image for a fresh service.create op —
  # control-plane side now that wokkud (not the dokku plugin) provisions the
  # container. Mirrors DatabaseService::DEDICATED_ENGINES (mysql is retired/grandfathered
  # only — a fresh dedicated create never sees it).
  DEFAULT_IMAGES = {
    "postgres" => "postgres:16", "mariadb" => "mariadb:11.4",
    "mongodb" => "mongo:7", "redis" => "redis:7"
  }.freeze

  # @param app [AppRecord] the app to attach the DB to (nil allowed for
  #   unlinked provisioning, e.g. via API)
  # @param service_type [String] "postgres" | "mysql" | ...
  # @param tier [String] "shared_free" | "basic" | "standard" | "performance"
  # @param name [String] optional explicit DB name
  def initialize(app:, service_type:, tier: DEFAULT_TIER, name: nil, creator: nil, server: nil, shape: nil)
    @app = app
    @service_type = service_type.to_s
    @tier = (tier.presence || DEFAULT_TIER).to_s
    @name = name.presence
    # App-less provisions (API standalone create) pass server: explicitly.
    @server = server || app&.server
    # Creator is the user who triggered the provision (dashboard /
    # API). Stored on DatabaseService so the policy scope can show
    # in-flight or unlinked addons in their list. Defaults to the app's
    # creator when not given (template deployer path).
    @creator = creator || app&.creator
    # Resources::Shape|nil — per-resource billing (spec 2026-09-24 §5.3):
    # when present, the row and the service.create op both get a
    # cpu/memory_mb (and disk_gb) size instead of the tier's fixed spec.
    @shape = shape
  end

  def call
    if shared?
      provision_shared!
    else
      provision_dedicated!
    end
  end

  # Run-spec for a service.ensure op on an ALREADY-PROVISIONED dedicated
  # service. Same fields provision_dedicated_via_ops! passes to service.create,
  # recomputed from the row + its tier — EXCEPT admin_pass, which is
  # deliberately empty here (the databasement credential boundary):
  #
  #   ensure recreates a MISSING container FROM ITS INTACT DATA. The engine
  #   image skips init on a non-empty data dir, so POSTGRES_PASSWORD / etc. is
  #   ignored — the superuser already lives in the data dir. And if the data
  #   dir is ABSENT, ensure REFUSES (data_dir_missing) rather than re-init. So
  #   admin_pass can never authenticate anything on this path; passing "" keeps
  #   this supervision loop from ever reading, storing, or logging a real
  #   credential (which lives only inside the container + the encrypted dsn).
  # Engine image for a wokkud service.create/ensure op. Tier `spec` may pin a
  # custom image — pgvector, postgis, timescaledb flavours where the extension
  # binary ships in the image (same convention CreateAddonJob honors on the
  # dokku path). MUST be used by ensure too: a supervision recreate with the
  # stock image would boot a pgvector DB without its extension binary.
  def self.image_for(db)
    spec = db.service_tier&.spec || {}
    if spec["image"].present?
      "#{spec['image']}:#{spec['image_version'].presence || 'latest'}"
    else
      DEFAULT_IMAGES.fetch(db.service_type) {
        raise ArgumentError, "dedicated #{db.service_type} is not supported on wokkud-managed servers yet"
      }
    end
  end

  def self.ensure_params_for(db)
    spec = db.service_tier&.spec || {}
    {
      service_type: db.service_type,
      image: image_for(db),
      memory_mb: spec["memory_mb"].to_i,
      max_connections: spec["connections"].to_i,
      network: DEDICATED_NETWORK,
      volume_path: "/var/lib/dokku/services/#{db.service_type}/#{db.name}/data",
      admin_pass: "", # inert on recreate — see method comment (credential boundary)
      database: db.service_type == "redis" ? "" : db.dedicated_db_name
    }
  end

  def self.destroy!(database_service:)
    # Farewell snapshot FIRST, outside any transaction and before any
    # teardown: the managed export is an async wokkud op (must be committed
    # to be claimable) and shared tenants' data must still exist when the
    # export runs — the old before_destroy hook could satisfy neither
    # (2026-07-24: 300s timeout inside the destroy transaction; shared
    # tenants exported after their DB was already dropped).
    database_service.farewell_snapshot!

    if database_service.shared?
      destroy_shared_tenant!(database_service)
      return
    end

    # Linked apps keep env pointing at this DB (<TYPE>_URL from create, or a
    # DATABASE_URL a link set) — drop exactly the vars still holding its DSN,
    # never one since repointed (2026-10-07: a dead MONGODB_URL lingered).
    release_dedicated_env!(database_service)

    # Phase B4: a dedicated service has no dokku plugin container to destroy
    # over SSH — tear it down via a service.destroy op.
    begin
      Services::Ops.issue_and_wait!(service: database_service, kind: "service.destroy", params: { force: true })
    rescue Services::Ops::Failed, Services::Ops::Timeout => e
      Rails.logger.warn "Dedicated destroy (wokkud) failed (may already be gone): #{e.message}"
    end
    database_service.destroy
  end

  # Env vars a shared redis tenant's destroy unsets on linked apps
  # (the keys Addons::SharedProvisioner#tenant_envs sets). Shared SQL
  # tenants follow the ownership rule in .shared_sql_env instead.
  SHARED_TENANT_ENV_KEYS = { "redis" => %w[REDIS_URL] }.freeze

  # Tears down a shared tenant (any engine) via a tenant.destroy op on its
  # PARENT row (C1 contract: op.service is the parent container, the slug
  # travels in params). Both legs are fail-soft — the env unset is a pure
  # EnvVar-row delete (W3: no SSH) and the host teardown tolerates
  # already-gone tenants (wokkud drops are IF-EXISTS) — the row always goes.
  def self.destroy_shared_tenant!(db)
    keys = SHARED_TENANT_ENV_KEYS.fetch(db.service_type, [])
    db.app_records.each do |app_record|
      if SHARED_PARENTS.key?(db.service_type)
        release_owned_env!(app_record, db)
      else
        Apps::EnvWriter.unset(app_record, *keys)
      end
    rescue => e
      Rails.logger.warn "Failed to unset #{keys.join(', ')} on #{app_record.name}: #{e.message}"
    end

    if (parent = db.parent_service)
      begin
        Services::Ops.issue_and_wait!(
          service: parent, kind: "tenant.destroy",
          params: { slug: shared_tenant_slug(db), force: true }
        )
      rescue => e
        Rails.logger.warn "tenant.destroy failed (may already be gone): #{e.message}"
      end
    else
      Rails.logger.warn "shared tenant #{db.name} has no parent row — skipping host teardown"
    end

    db.destroy
  end

  # Env ownership for shared SQL tenants (review fixes 2 + 13): key => the
  # value THIS tenant sets. A tenant sets a key only when the app has none
  # (never clobbering a dedicated DB's or another tenant's URL), and its
  # destroy removes a key only while it still holds this tenant's value.
  def self.shared_sql_env(service_type, url)
    case service_type
    when "postgres" then { "DATABASE_URL" => url }
    # MARIADB_URL: same name + scheme as a dedicated mariadb; DATABASE_URL
    # in the mysql2:// scheme Rails' adapter wants.
    when "mariadb"  then { "MARIADB_URL" => url, "DATABASE_URL" => mysql2_url(url) }
    else {}
    end
  end

  # Ops pre-warm (rake wokku:shared:ensure_parents): ensure a server's shared
  # parent so the first customer attach doesn't pay the image pull + init
  # inside a dashboard request. mariadb parents are born here if missing;
  # a postgres parent can't be created from nothing (it is adopted), so only
  # an existing row is ensured. Returns the parent row, or nil if skipped.
  def self.ensure_shared_parent!(server:, engine:)
    raise ArgumentError, "no shared parent for #{engine.inspect}" unless SHARED_PARENTS.key?(engine)

    provisioner = new(app: nil, service_type: engine, tier: SHARED_TIER, server: server)
    parent = if engine == "mariadb"
      provisioner.send(:find_or_create_parent_record!)
    else
      DatabaseService.find_by(server: server, name: SHARED_PARENTS[engine])
    end
    return nil unless parent

    provisioner.send(:ensure_shared_parent!, parent)
    parent
  end

  # Values are encrypted (non-deterministic), so compare in Ruby.
  def self.release_owned_env!(app_record, db)
    if db.dsn.blank?
      # Legacy pg tenants adopted without a stored dsn can't prove ownership:
      # keep the historical unconditional unset for them.
      Apps::EnvWriter.unset(app_record, "DATABASE_URL") if db.service_type == "postgres"
      return
    end
    shared_sql_env(db.service_type, db.dsn).each do |key, value|
      row = app_record.env_vars.find_by(key: key)
      row.destroy if row && row.value == value
    end
  end

  def self.release_dedicated_env!(db)
    return if db.dsn.blank?
    values = [ db.dsn, mysql2_url(db.dsn) ]
    # value is non-deterministically encrypted — compare in Ruby, not SQL.
    db.app_records.each { |app_record| app_record.env_vars.select { |e| values.include?(e.value) }.each(&:destroy) }
  end

  # Rails' mysql2 adapter wants the mysql2:// scheme in DATABASE_URL.
  def self.mysql2_url(dsn) = dsn.sub(/\Amysql:/, "mysql2:")

  # The host-side tenant slug for a shared row. shared_db_name is canonical
  # (== the slug for every engine since W7 Phase 3); older rows fall back to
  # the role name (pg: "<slug>_role", redis: "<slug>") and, for engines that
  # stored neither (memcached), to the row-name convention
  # "<slug>-<engine>-shared-<hex>" / "<slug>-pg-shared-<hex>".
  def self.shared_tenant_slug(db)
    db.shared_db_name.presence ||
      db.shared_role_name.to_s.sub(/_role\z/, "").presence ||
      db.name.to_s.sub(/-(?:pg|#{Regexp.escape(db.service_type)})-shared-\h+\z/, "")
  end

  # Public entry for provisioning a row someone else already created
  # (CreateAddonJob) — same ops stanza as the fresh-create path.
  def provision_existing!(db)
    provision_dedicated_via_ops!(db, db.name)
  end

  private

  def shared?
    @tier == SHARED_TIER && SHARED_PARENTS.key?(@service_type)
  end

  def default_name
    base = @app ? @app.name : "shared-#{SecureRandom.hex(3)}"
    "#{base}-#{@service_type}"
  end

  def provision_dedicated!
    # B4 gate 5 review fix: this used to be a KeyError→ArgumentError raised
    # from INSIDE provision_dedicated_via_ops!, i.e. AFTER DatabaseService
    # .create! below had already inserted a row and BEFORE
    # app.app_databases.create! ran — so rollback_partial_deploy! (which
    # iterates app.app_databases) never saw the orphan, leaving it stuck in
    # status "creating" forever (hit by huly/tubearchivist/zincsearch's
    # elasticsearch, which has no wokkud image mapping). Pre-flight guard,
    # mirrored on TemplateDeployer's pre-flight engine guard: raise before any
    # row exists. DatabaseService::DEDICATED_ENGINES is the canonical supported-engine
    # list (mirrors DEFAULT_IMAGES.keys exactly).
    unless DatabaseService::DEDICATED_ENGINES.include?(@service_type)
      raise ArgumentError, "dedicated #{@service_type} is not supported on wokkud-managed servers yet"
    end

    name = @name || default_name
    attrs = {
      name: name,
      service_type: @service_type,
      server: @server,
      status: :creating,
      tier_name: @tier,
      shared: false,
      creator: @creator
    }
    attrs.merge!(cpu: @shape.cpu, memory_mb: @shape.memory_mb, disk_gb: @shape.disk_gb) if @shape
    db = DatabaseService.create!(attrs)

    provision_dedicated_via_ops!(db, name)

    db.update!(status: :running)
    db
  end

  # Fresh-create path on a flagged server: control plane generates the admin
  # password, issues a service.create op, and (since there's no dokku plugin
  # :link on this path) wires DATABASE_URL itself. Marks the row
  # wokkud_managed so tier changes / .destroy! route future operations on it
  # back through ops too.
  def provision_dedicated_via_ops!(db, name)
    admin_pass = SecureRandom.hex(16)
    spec = db.service_tier&.spec || {}
    Services::Ops.issue_and_wait!(
      service: db, kind: "service.create",
      params: {
        service_type: @service_type,
        # B4 gate 5 friendly refusal lives in image_for; tier-spec images
        # (pgvector et al.) win over the stock DEFAULT_IMAGES entry.
        image: self.class.image_for(db),
        memory_mb: db.memory_mb || spec["memory_mb"].to_i,
        cpu: db.cpu&.to_f,
        max_connections: db.memory_mb ? db.max_connections_for_shape : spec["connections"].to_i,
        network: DEDICATED_NETWORK,
        volume_path: "/var/lib/dokku/services/#{@service_type}/#{name}/data",
        admin_pass: admin_pass,
        # Task 10: the engine creates this application database on first boot
        # (POSTGRES_DB / MARIADB_DATABASE / MONGO_INITDB_DATABASE). Underscored
        # dedicated_db_name is the one source of truth backup/restore/the DSN
        # all use. Redis has no database concept — send "" so wokkud adds no
        # DB-creation env.
        database: @service_type == "redis" ? "" : db.dedicated_db_name
      }
    )
    dsn = compose_dsn(db, admin_pass)
    db.update!(wokkud_managed: true, dsn: dsn)
    return unless @app

    Apps::EnvWriter.set(@app, { "#{@service_type.upcase}_URL" => dsn })
    # The DSN host is the container NAME, which resolves via Docker DNS on
    # the wokku-services overlay — the service joins it at create
    # (network: DEDICATED_NETWORK above) and every app's Swarm tasks already
    # run on it (Lifecycle::Ops converge networks). The old dokku bridge
    # attach for non-native apps died with the dokku runtime.
    @app.app_databases.create!(database_service: db, alias_name: @service_type.upcase)
  end

  # HOST is the hyphenated container name (`dokku.<type>.<name>`, resolves via
  # Docker DNS); the trailing DATABASE segment is the UNDERSCORED
  # dedicated_db_name so DSN, the engine-created database, and backup/restore
  # all agree on one spelling. Redis has no database — keep `/0`.
  def compose_dsn(db, pass)
    host = "dokku.#{@service_type}.#{db.name}"
    db_name = db.dedicated_db_name
    case @service_type
    when "mariadb", "mysql" then "mysql://root:#{pass}@#{host}:3306/#{db_name}"
    # root is created in the admin DB (MONGO_INITDB_ROOT_*); without
    # authSource, drivers authenticate against the path database and fail.
    when "mongodb"          then "mongodb://root:#{pass}@#{host}:27017/#{db_name}?authSource=admin"
    when "redis"            then "redis://:#{pass}@#{host}:6379/0"
    else "postgres://postgres:#{pass}@#{host}:5432/#{db_name}"
    end
  end

  def provision_shared!
    raise Error, "Shared tier requires a postgres or mariadb service_type" unless SHARED_PARENTS.key?(@service_type)

    parent = find_or_create_parent_record!
    slug = @app ? @app.name : "shared-#{SecureRandom.hex(3)}"
    # Plan bundle: each plan ships with 1 shared DB up to plan.db_bundle_mb
    # (== Plan#shared_tenant_cap for SQL engines — keep them in step).
    # Fall back to the plugin default if the creator has no plan resolution
    # (e.g. seeded fixtures or system-owned tenants).
    quota_mb = @creator&.current_plan&.db_bundle_mb || DEFAULT_SHARED_STORAGE_MB

    # The mariadb parent is born by wokkud on its first service.ensure — it
    # must be up before a tenant can exist on it (no-op once it runs).
    ensure_shared_parent!(parent) if @service_type == "mariadb"
    tenant = provision_tenant_via_ops!(parent: parent, slug: slug, quota_mb: quota_mb)

    db = DatabaseService.create!(
      name: "#{slug}-#{@service_type == 'postgres' ? 'pg' : @service_type}-shared-#{SecureRandom.hex(3)}",
      service_type: @service_type,
      server: @server,
      status: :running,
      tier_name: SHARED_TIER,
      shared: true,
      parent_service: parent,
      shared_role_name: tenant[:role],
      shared_db_name: tenant[:db],
      storage_mb_quota: quota_mb,
      creator: @creator,
      wokkud_managed: parent.wokkud_managed?,
      dsn: tenant[:connection_url]
    )

    if @app
      Apps::EnvWriter.set(@app, shared_envs(tenant[:connection_url]))
      # The DATABASE_URL host (`dokku-shared-<engine>`) is the PARENT
      # container name, which only resolves on the wokku-services overlay —
      # the network every app's Swarm tasks run on. service.ensure attaches
      # the parent idempotently (agent-side, exists-path). The old dokku
      # bridge attach for non-native apps died with the dokku runtime.
      ensure_shared_parent!(parent)
      @app.app_databases.create!(database_service: db, alias_name: @service_type == "postgres" ? "DATABASE" : "MARIADB")
    end

    db
  end

  def ensure_shared_parent!(parent)
    raise Error, "shared parent #{parent.name} is not wokkud-managed — cannot ensure overlay attachment" unless parent.wokkud_managed?
    Services::Ops.issue_and_wait!(service: parent, kind: "service.ensure", params: {})
  end

  # Only keys the app doesn't have yet — see .shared_sql_env.
  def shared_envs(url)
    self.class.shared_sql_env(@service_type, url).reject { |key, _| @app.env_vars.exists?(key: key) }
  end

  # Phase B4: the shared-postgres PARENT container is never created via
  # service.create (wokkud's tenant runtime only supports operating on an
  # already-adopted parent — see carry-forward note / wokkud's
  # TenantProvisionParams "shared parents only"). Once that parent is
  # wokkud_managed, new TENANTS on it are provisioned via a tenant.provision
  # op instead of shelling out to the dokku-shared-postgres plugin. Role/db
  # naming and the connection URL mirror wokkud's pgProvisionTenant exactly
  # (CREATE ROLE "<slug>_role" ... ; CREATE DATABASE "<slug>" ...).
  def provision_tenant_via_ops!(parent:, slug:, quota_mb:)
    password = SecureRandom.hex(16)
    begin
      Services::Ops.issue_and_wait!(
        service: parent, kind: "tenant.provision",
        params: { slug: slug, password: password, quota_mb: quota_mb, max_connections: 40 }
      )
    rescue Services::Ops::Failed => e
      raise unless e.op.error_code == "tenant_exists"
      # Idempotent: a prior attempt already provisioned this tenant on the
      # host (same handling as Addons::SharedProvisioner's already_attached?
      # short-circuit) — don't blow up the request. The plugin has no
      # "fetch existing tenant's password" op, so the FRESH password above
      # was never actually set on the role — composing a DSN with it would
      # silently break the app's DB connection. Reuse the DSN stored on the
      # child row from the original successful provision instead.
      existing = parent.child_services.find_by(shared_db_name: slug, status: :running)
      if existing.blank? || existing.dsn.blank?
        raise Error, "tenant_exists for #{slug.inspect} but no reusable DatabaseService row with a stored dsn was found"
      end
      return { role: existing.shared_role_name, db: existing.shared_db_name, connection_url: existing.dsn }
    end
    if @service_type == "mariadb"
      # Mirrors wokkud's mariadbProvisionTenant: user = database = slug.
      return { role: slug, db: slug, connection_url: "mysql://#{slug}:#{password}@#{SHARED_MARIADB_PARENT}:3306/#{slug}" }
    end
    {
      role: "#{slug}_role",
      db: slug,
      connection_url: "postgres://#{slug}_role:#{password}@#{SHARED_PG_NETWORK}:5432/#{slug}"
    }
  end

  # Bookkeeping parent row representing the shared host container itself,
  # so all shared tenants point at a single server-scoped parent. Find-or-create
  # so concurrent provisions don't race.
  def find_or_create_parent_record!
    DatabaseService.find_or_create_by!(
      server: @server,
      name: SHARED_PARENTS.fetch(@service_type),
      service_type: @service_type
    ) do |r|
      r.status = :running
      r.tier_name = "shared_host"
      r.shared = false
      # wokkud births the mariadb parent itself (first service.ensure); the
      # postgres parent is adopted, which is what marks it managed.
      r.wokkud_managed = true if @service_type == "mariadb"
    end
  end
end
