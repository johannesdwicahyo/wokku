module Addons
  # Bundle v2 (see memory/project_bundle_v2_locked_spec.md): every app
  # box auto-attaches the full shared backend stack at create time.
  # This service is the engine-agnostic entry point — call it once per
  # engine per box.
  #
  # Engines:
  #   * postgres / mariadb — DatabaseProvisioner shared path (tenant.provision op)
  #   * redis — same wokkud tenant-op
  #     contract, issued here against the engine's shared PARENT row
  #     (W7 Phase 3: was the dokku-shared-* plugins over SSH).
  #
  # Idempotent: skip provisioning if the app already has a shared
  # tenant of the same engine attached. Safe to re-run on redeploy.
  class SharedProvisioner
    SUPPORTED_ENGINES = DatabaseService::SHARED_ENGINES

    # Engine → metadata used by the generic provisioner branch.
    # alias_env: env name used for the AppDatabase alias column.
    # parent_name: name of the shared parent DatabaseService row AND the
    #   parent container (= the DSN host, resolvable on the wokku-services
    #   overlay every app task runs on).
    ENGINE_CONFIG = {
      "redis"     => { alias_env: "REDIS",     parent_name: "dokku-shared-redis" }
    }.freeze

    class UnsupportedEngine < StandardError; end

    def initialize(app:, engine:)
      @app    = app
      @engine = engine.to_s
    end

    def self.feature_enabled?
      ENV["BUNDLE_V2_ENABLED"].to_s.downcase.in?(%w[1 true yes on])
    end

    def call
      return :feature_disabled  unless self.class.feature_enabled?
      return :unsupported       unless SUPPORTED_ENGINES.include?(@engine)
      return :missing_server    if @app.server.nil?
      return :already_attached  if already_attached?

      provision!
      :provisioned
    end

    private

    def already_attached?
      # Only a fully provisioned (:running) tenant counts as attached. A
      # :creating or :error row is a prior in-flight/failed attempt that a
      # retry must be allowed to resume — see #provision_generic!.
      @app.database_services.where(service_type: @engine, shared: true, status: :running).exists?
    end

    def provision!
      if DatabaseProvisioner::SHARED_PARENTS.key?(@engine)
        provision_sql!
      else
        provision_generic!
      end
    end

    def provision_sql!
      DatabaseProvisioner.new(
        app: @app,
        service_type: @engine,
        tier: DatabaseProvisioner::SHARED_TIER,
        creator: @app.creator
      ).call
    end

    def provision_generic!
      config = ENGINE_CONFIG.fetch(@engine) do
        raise UnsupportedEngine, "no engine config for #{@engine.inspect}"
      end

      parent = find_or_create_parent_record!(config[:parent_name])

      # Record-first: a durable, app-linked :creating row exists before any
      # host call, so the addon is visible immediately and a retry can find
      # and resume this exact row (the link is what makes it reachable via
      # @app.database_services, a has_many :through).
      db = find_or_initialize_working_row(config, parent)
      @app.transaction do
        db.save! if db.new_record?
        @app.app_databases.find_or_create_by!(database_service: db) do |ad|
          ad.alias_name = config[:alias_env]
        end
      end

      slug     = tenant_slug
      password = SecureRandom.hex(16)
      begin
        provision_tenant_via_ops!(parent, slug, password)
        envs = tenant_envs(config[:parent_name], slug, password)
        db.update!(
          shared_role_name: slug,
          shared_db_name: slug,
          dsn: envs.values.first,
          wokkud_managed: parent.wokkud_managed?
        )
        Apps::EnvWriter.set(@app, envs)
        # The DSN host is the PARENT container name, which only resolves on
        # the wokku-services overlay every app's Swarm tasks run on (B5a
        # attached parents under both names; shared-redis was unreachable
        # until a manual attach, 2026-07-22). service.ensure attaches the
        # parent idempotently. The old dokku bridge attach for non-native
        # apps died with the dokku runtime — no dokku-created app container
        # exists to attach anymore.
        ensure_parent_on_overlay!(parent)
        db.update!(status: :running)
        db
      rescue => e
        # Compensate: drop any host tenant this attempt created so the retry's
        # tenant.provision starts clean (wokkud's destroy is IF-EXISTS, so a
        # tenant that never materialized succeeds silently).
        begin
          Services::Ops.issue_and_wait!(
            service: parent, kind: "tenant.destroy", params: { slug: slug, force: true }
          )
        rescue StandardError
          # best-effort cleanup; the :error row + re-raise are what matter
        end
        db.update!(status: :error)
        raise
      end
    end

    # The host-side tenant slug: the app name as-is (byte-parity with the
    # plugin era).
    def tenant_slug
      @app.name
    end

    # Same tenant-op contract as DatabaseProvisioner#provision_tenant_via_ops!
    # (C1: op.service is the PARENT, slug travels in params, CP generates the
    # password). tenant_exists means a prior half-finished attempt
    # left the host tenant behind while the row never reached :running —
    # nothing is using it (already_attached? would have short-circuited), so
    # recycle: destroy the leftover and provision cleanly with the fresh
    # password.
    def provision_tenant_via_ops!(parent, slug, password)
      params = { slug: slug, password: password }
      Services::Ops.issue_and_wait!(service: parent, kind: "tenant.provision", params: params)
    rescue Services::Ops::Failed => e
      raise unless e.op.error_code == "tenant_exists"
      Services::Ops.issue_and_wait!(
        service: parent, kind: "tenant.destroy", params: { slug: slug, force: true }
      )
      Services::Ops.issue_and_wait!(service: parent, kind: "tenant.provision", params: params)
    end

    # CP-composed env values, byte-compatible with what the dokku-shared-*
    # plugins emitted (same scheme/host/port shapes) so new tenants look
    # exactly like existing ones. Host is the parent container name.
    def tenant_envs(host, slug, password)
      { "REDIS_URL" => "redis://#{slug}:#{password}@#{host}:6379/0" }
    end

    # Find the in-flight/failed row for this (app, engine) to resume, or build
    # a fresh :creating row. Only non-:running rows are candidates — a :running
    # row would have short-circuited at already_attached?.
    def find_or_initialize_working_row(config, parent)
      existing = @app.database_services.find_by(
        service_type: @engine, shared: true, status: %i[creating error]
      )
      return existing if existing

      DatabaseService.new(
        name: "#{@app.name}-#{@engine}-shared-#{SecureRandom.hex(3)}",
        service_type: @engine,
        server: @app.server,
        status: :creating,
        tier_name: DatabaseProvisioner::SHARED_TIER,
        shared: true,
        parent_service: parent,
        creator: @app.creator
      )
    end

    def find_or_create_parent_record!(parent_name)
      DatabaseService.find_or_create_by!(
        server: @app.server,
        name: parent_name,
        service_type: @engine
      ) do |r|
        r.status = :running
        r.tier_name = "shared_host"
        r.shared = false
      end
    end

    # service.ensure on an EXISTING container attaches it to the
    # wokku-services overlay (agent-side, idempotent) — the only network an
    # app's Swarm tasks can resolve it on. A missing parent surfaces
    # loudly (data_dir_missing) — that's an incident, not an attach problem.
    def ensure_parent_on_overlay!(parent)
      raise UnsupportedEngine, "parent #{parent.name} is not wokkud-managed — cannot ensure overlay attachment" unless parent.wokkud_managed?
      Services::Ops.issue_and_wait!(service: parent, kind: "service.ensure", params: {})
    end
  end
end
