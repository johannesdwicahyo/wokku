# Central provisioning path for database add-ons. Branches between dedicated
# (Dokku postgres:create-per-tenant) and shared (Dokku::SharedPostgres) so
# every caller — controllers, API, template deployer — uses one code path.
class DatabaseProvisioner
  class Error < StandardError; end

  SHARED_TIER = "shared_free".freeze
  DEFAULT_TIER = "basic".freeze

  # @param app [AppRecord] the app to attach the DB to (nil allowed for
  #   unlinked provisioning, e.g. via API)
  # @param service_type [String] "postgres" | "mysql" | ...
  # @param tier [String] "shared_free" | "basic" | "standard" | "performance"
  # @param name [String] optional explicit DB name
  # @param client [Dokku::Client] optional pre-built client (for reuse)
  def initialize(app:, service_type:, tier: DEFAULT_TIER, name: nil, client: nil)
    @app = app
    @service_type = service_type.to_s
    @tier = (tier.presence || DEFAULT_TIER).to_s
    @name = name.presence
    @server = app&.server
    @client = client
  end

  def call
    if shared?
      provision_shared!
    else
      provision_dedicated!
    end
  end

  def self.destroy!(database_service:, client: nil)
    client ||= Dokku::Client.new(database_service.server)

    if database_service.shared?
      destroy_shared_tenant!(database_service, client)
    else
      begin
        Dokku::Databases.new(client).destroy(database_service.service_type, database_service.name)
      rescue => e
        Rails.logger.warn "Dedicated destroy failed (may already be gone): #{e.message}"
      end
      database_service.destroy
    end
  end

  # Tears down a shared tenant. When `shared_client` is nil (production path),
  # runs the two independent SSH operations in parallel with fresh Net::SSH
  # connections per thread — halves wall-clock time (~30s → ~15s). When a
  # client is passed (tests/mocks), runs sequentially on that client since
  # StubClient usually isn't thread-safe and parallelism would just add noise.
  def self.destroy_shared_tenant!(db, shared_client)
    apps = db.app_records.to_a

    unset_db_url = ->(c) do
      apps.each do |app_record|
        Dokku::Config.new(c).unset(app_record.name, "DATABASE_URL")
      rescue => e
        Rails.logger.warn "Failed to unset DATABASE_URL on #{app_record.name}: #{e.message}"
      end
    end

    drop_tenant = ->(c) do
      Dokku::SharedPostgres.new(c).destroy_tenant!(
        role_name: db.shared_role_name,
        db_name: db.shared_db_name
      )
    rescue => e
      Rails.logger.warn "destroy_tenant! failed: #{e.message}"
    end

    if shared_client
      unset_db_url.call(shared_client)
      drop_tenant.call(shared_client)
    else
      threads = [
        Thread.new { unset_db_url.call(Dokku::Client.new(db.server)) },
        Thread.new { drop_tenant.call(Dokku::Client.new(db.server)) }
      ]
      threads.each(&:join)
    end

    db.destroy
  end

  private

  def shared?
    @tier == SHARED_TIER && @service_type == "postgres"
  end

  def client
    @client ||= Dokku::Client.new(@server)
  end

  def default_name
    base = @app ? @app.name : "shared-#{SecureRandom.hex(3)}"
    "#{base}-#{@service_type}"
  end

  def provision_dedicated!
    name = @name || default_name
    db = DatabaseService.create!(
      name: name,
      service_type: @service_type,
      server: @server,
      status: :creating,
      tier_name: @tier,
      shared: false
    )
    Dokku::Databases.new(client).create(@service_type, name)
    if @app
      Dokku::Databases.new(client).link(@service_type, name, @app.name)
      @app.app_databases.create!(database_service: db, alias_name: @service_type.upcase)
    end
    db.update!(status: :running)
    db
  end

  def provision_shared!
    raise Error, "Shared tier requires a postgres service_type" unless @service_type == "postgres"

    shared = Dokku::SharedPostgres.new(client)
    shared.ensure_host!

    slug = @app ? @app.name : "shared-#{SecureRandom.hex(3)}"
    tenant = shared.provision_tenant!(slug: slug)

    parent = find_or_create_parent_record!

    db = DatabaseService.create!(
      name: "#{slug}-pg-shared-#{SecureRandom.hex(3)}",
      service_type: "postgres",
      server: @server,
      status: :running,
      tier_name: SHARED_TIER,
      shared: true,
      parent_service: parent,
      shared_role_name: tenant[:role_name],
      shared_db_name: tenant[:db_name],
      connection_limit: tenant[:connection_limit],
      storage_mb_quota: Dokku::SharedPostgres::DEFAULT_STORAGE_MB
    )

    if @app
      url = shared.connection_string(
        role_name: tenant[:role_name],
        db_name: tenant[:db_name],
        password: tenant[:password]
      )
      Dokku::Config.new(client).set(@app.name, { "DATABASE_URL" => url })
      @app.app_databases.create!(database_service: db, alias_name: "DATABASE")
    end

    db
  end

  # Bookkeeping parent row representing the shared host container itself,
  # so all shared tenants point at a single server-scoped parent. Find-or-create
  # so concurrent provisions don't race.
  def find_or_create_parent_record!
    DatabaseService.find_or_create_by!(
      server: @server,
      name: Dokku::SharedPostgres::SHARED_CONTAINER_NAME,
      service_type: "postgres"
    ) do |r|
      r.status = :running
      r.tier_name = "shared_host"
      r.shared = false
    end
  end
end
