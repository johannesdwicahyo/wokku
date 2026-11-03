# Provisions a fresh dedicated database container for engines that have
# no shared variant (MySQL, Mongo). Bundle v2 REVISED 2026-05-31:
# DatabaseServiceUpgrade routes here for these engines instead of the
# Pg/Redis migration jobs.
#
# Five-step state machine (no migration, no shared cleanup):
#   1. provision dedicated container (wokkud service.create op)
#   2. set <ENGINE>_URL on the app
#   3. link AppDatabase row with the right alias
#   4. restart app (converge re-reads runtime_env)
#   5. mark dedicated row :running
#
# Retries OFF — half-provisioned container shouldn't replay automatically.
class CreateDedicatedDatabaseJob < ApplicationJob
  queue_as :default
  retry_on StandardError, attempts: 1

  # Per-engine: alias name in AppDatabase + env var the app reads.
  ENGINE_CONFIG = {
    "mysql"   => { alias_name: "DATABASE", env: "DATABASE_URL" },
    "mariadb" => { alias_name: "DATABASE", env: "DATABASE_URL" },
    "mongodb" => { alias_name: "DATABASE", env: "DATABASE_URL" }
  }.freeze

  def perform(dedicated_db_id)
    dedicated = DatabaseService.find(dedicated_db_id)
    app       = first_app_for_dedicated(dedicated)
    config    = ENGINE_CONFIG.fetch(dedicated.service_type)

    begin
      provision!(dedicated)
      dedicated.update!(status: :upgrading_cutover)

      cutover!(dedicated: dedicated, app: app, config: config)

      dedicated.update!(status: :running)

      Activity.log(
        user: app.creator, team: app.team,
        action: "addons.dedicated_db.created",
        target: app,
        metadata: { engine: dedicated.service_type, dedicated_id: dedicated.id }
      )
    rescue => e
      rollback!(dedicated, e)
      raise
    end
  end

  private

  # The app that triggered the upgrade — for fresh-create flows the
  # dedicated row has no upgrade_source, so we resolve via the creator's
  # most recent app instead (DatabaseServiceUpgrade always reserves the
  # row inside the user's transaction during a box-creation flow, so
  # this is the right "owning" app at job-pickup time).
  def first_app_for_dedicated(dedicated)
    # When called from the box-creation flow, the app is the one being
    # created — the controller links it via AppDatabase before enqueueing.
    # Fall back to looking up the AppDatabase row if present.
    AppDatabase.where(database_service: dedicated).first&.app_record \
      || raise(UpgradeError::ProvisioningFailed, "no app linked to dedicated #{dedicated.id}")
  end

  # Per-engine image for a fresh service.create op — control-plane side now
  # that wokkud (not the dokku plugin) provisions the container. Only the
  # ENGINE_CONFIG engines land here.
  DEFAULT_IMAGES = {
    "mysql" => "mysql:9.6.0", "mariadb" => "mariadb:11.4", "mongodb" => "mongo:7"
  }.freeze

  def provision!(dedicated)
    admin_pass = SecureRandom.hex(16)
    spec = dedicated.service_tier&.spec || {}
    Services::Ops.issue_and_wait!(
      service: dedicated, kind: "service.create",
      params: {
        service_type: dedicated.service_type,
        # B4 gate 5: friendly refusal instead of a bare KeyError for
        # engines with no wokkud image mapping (clickhouse, nats, …).
        image: DEFAULT_IMAGES.fetch(dedicated.service_type) {
          raise ArgumentError, "dedicated #{dedicated.service_type} is not supported on wokkud-managed servers yet"
        },
        # A builder-shaped row wins over its tier (same as DatabaseProvisioner).
        memory_mb: dedicated.memory_mb || spec["memory_mb"].to_i,
        max_connections: dedicated.memory_mb ? dedicated.max_connections_for_shape : spec["connections"].to_i,
        **(dedicated.cpu ? { cpu: dedicated.cpu.to_f } : {}),
        network: DatabaseProvisioner::DEDICATED_NETWORK,
        volume_path: "/var/lib/dokku/services/#{dedicated.service_type}/#{dedicated.name}/data",
        admin_pass: admin_pass
      }
    )
    dedicated.update!(wokkud_managed: true, dsn: compose_dsn(dedicated, admin_pass))
  end

  def compose_dsn(dedicated, pass)
    host = "dokku.#{dedicated.service_type}.#{dedicated.name}"
    case dedicated.service_type
    when "mariadb", "mysql" then "mysql://root:#{pass}@#{host}:3306/#{dedicated.name}"
    when "mongodb"          then "mongodb://root:#{pass}@#{host}:27017/#{dedicated.name}"
    else "postgres://postgres:#{pass}@#{host}:5432/#{dedicated.name}"
    end
  end

  def cutover!(dedicated:, app:, config:)
    # Op-created services carry their own control-plane-generated DSN
    # (Task 1 encryption). Its host is the container NAME, which resolves
    # via Docker DNS on the wokku-services overlay — the service joins it at
    # create and every app's Swarm tasks already run on it (Lifecycle::Ops
    # converge networks). The old dokku bridge attach for non-native apps
    # died with the dokku runtime.
    Apps::EnvWriter.set(app, { config[:env] => dedicated.dsn })
    # Restart through wokkud (stack.converge re-reads the app's runtime_env).
    Apps::Restarter.restart(app)
  end

  def rollback!(dedicated, error)
    # Canonical managed teardown — mirrors DatabaseProvisioner.destroy!'s
    # wokkud stanza. The container may never have been created (provision op
    # failed); wokkud reports that as a Failed op we log and move past.
    begin
      Services::Ops.issue_and_wait!(service: dedicated, kind: "service.destroy", params: { force: true })
    rescue StandardError => e
      Rails.logger.warn "CreateDedicatedDatabaseJob rollback: wokkud destroy failed (may already be gone): #{e.message}"
    end
    dedicated.destroy!
    Sentry.capture_exception(error, extra: { dedicated_id: dedicated.id }) if defined?(Sentry)
  end
end
