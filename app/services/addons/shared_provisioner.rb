module Addons
  # Bundle v2 (see memory/project_bundle_v2_locked_spec.md): every app
  # box auto-attaches the full shared backend stack at create time.
  # This service is the engine-agnostic entry point — call it once per
  # engine per box.
  #
  # Engines:
  #   * postgres     — Dokku::SharedPostgres (via DatabaseProvisioner shared path)
  #   * redis        — Dokku::SharedRedis
  #   * memcached    — Dokku::SharedMemcached
  #   * rabbitmq     — Dokku::SharedRabbitmq
  #   * meilisearch  — Dokku::SharedMeilisearch
  #
  # Idempotent: skip provisioning if the app already has a shared
  # tenant of the same engine attached. Safe to re-run on redeploy.
  class SharedProvisioner
    SUPPORTED_ENGINES = %w[postgres redis memcached rabbitmq meilisearch].freeze

    # Engine → metadata used by the generic provisioner branch.
    # service_class: Dokku::Shared* wrapper class (must respond to
    #   #provision_tenant!(slug:) returning { envs: {...}, ... }).
    # alias_env: env name used for the AppDatabase alias column.
    # parent_name: stable name for the bookkeeping parent DatabaseService row.
    ENGINE_CONFIG = {
      "redis"       => { service_class: "Dokku::SharedRedis",       alias_env: "REDIS",       parent_name: "dokku-shared-redis" },
      "memcached"   => { service_class: "Dokku::SharedMemcached",   alias_env: "MEMCACHED",   parent_name: "dokku-shared-memcached" },
      "rabbitmq"    => { service_class: "Dokku::SharedRabbitmq",    alias_env: "RABBITMQ",    parent_name: "dokku-shared-rabbitmq" },
      "meilisearch" => { service_class: "Dokku::SharedMeilisearch", alias_env: "MEILISEARCH", parent_name: "dokku-shared-meilisearch" }
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
      @app.database_services.where(service_type: @engine, shared: true).exists?
    end

    def provision!
      if @engine == "postgres"
        provision_postgres!
      else
        provision_generic!
      end
    end

    def provision_postgres!
      DatabaseProvisioner.new(
        app: @app,
        service_type: "postgres",
        tier: DatabaseProvisioner::SHARED_TIER,
        creator: @app.creator
      ).call
    end

    def provision_generic!
      config = ENGINE_CONFIG.fetch(@engine) do
        raise UnsupportedEngine, "no engine config for #{@engine.inspect}"
      end

      client  = Dokku::Client.new(@app.server)
      service = config[:service_class].constantize.new(client)

      slug   = @app.name
      tenant = service.provision_tenant!(slug: slug)

      parent = find_or_create_parent_record!(config[:parent_name])

      db = DatabaseService.create!(
        name: "#{slug}-#{@engine}-shared-#{SecureRandom.hex(3)}",
        service_type: @engine,
        server: @app.server,
        status: :running,
        tier_name: DatabaseProvisioner::SHARED_TIER,
        shared: true,
        parent_service: parent,
        shared_role_name: tenant[:role],
        shared_db_name: tenant[:vhost],
        creator: @app.creator
      )

      Dokku::Config.new(client).set(@app.name, tenant[:envs])
      @app.app_databases.create!(database_service: db, alias_name: config[:alias_env])

      db
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
  end
end
