# Promotes a shared Pg tenant to a dedicated wokkud-managed postgres
# container. Six-step state machine:
#   1. provision dedicated container (service.create op via DatabaseProvisioner)
#   2. export shared tenant (service.export op on the shared parent → R2)
#   3. import into dedicated (service.import op)
#   4. flip DATABASE_URL + relink AppDatabase
#   5. restart app (converge waits — no separate health poll needed)
#   6. schedule DropSharedTenantJob 24h out
#
# Retries are explicitly OFF — a half-migrated DB must not be replayed.
# User retries via "Try again" button on the failed card.
class UpgradeSharedPgToDedicatedJob < ApplicationJob
  queue_as :default
  retry_on StandardError, attempts: 1

  ENV_KEY = "DATABASE_URL".freeze

  def perform(dedicated_db_id)
    dedicated = DatabaseService.find(dedicated_db_id)
    shared    = dedicated.upgrade_source
    app       = shared.app_records.first
    # Captured pre-cutover so rollback can restore the exact URL the app was
    # running on (older shared rows may predate the dsn column).
    original_url = app.runtime_env[ENV_KEY]

    begin
      provision_container!(dedicated)
      dedicated.update!(status: :upgrading_migrating)

      migrate_data!(shared: shared, dedicated: dedicated)
      dedicated.update!(status: :upgrading_cutover)

      cutover!(dedicated: dedicated, shared: shared, app: app)

      dedicated.update!(status: :running)
      shared.update!(status: :pending_destroy, pending_destroy_at: 24.hours.from_now)
      DropSharedTenantJob.set(wait: 24.hours).perform_later(shared.id)

      Activity.log(
        user: app.creator,
        team: app.team,
        action: "addons.upgrade_to_dedicated.completed",
        target: app,
        metadata: { shared_id: shared.id, dedicated_id: dedicated.id }
      )
    rescue => e
      rollback!(dedicated, shared, app, e, original_url)
      raise
    end
  end

  private

  # Same ops stanza as CreateAddonJob (service.create + CP-composed DSN).
  # app: nil — the env flip + AppDatabase relink happen at cutover, AFTER
  # the data is migrated, not at provision time.
  def provision_container!(dedicated)
    DatabaseProvisioner
      .new(app: nil, service_type: dedicated.service_type, tier: dedicated.tier_name,
           name: dedicated.name, server: dedicated.server, creator: dedicated.creator)
      .provision_existing!(dedicated)
  end

  # export-op -> R2 -> import-op relay through the server's backup
  # destination (mirrors BackupService/RestoreService's managed path).
  # Errors (Services::Ops::Failed/Timeout) propagate to #perform's rescue,
  # which rolls back the half-migrated dedicated container.
  def migrate_data!(shared:, dedicated:)
    destination = dedicated.server.backup_destination
    key = "migrations/#{dedicated.id}.gz"

    put_url = destination.s3_presigned_put(key)
    Services::Ops.issue_and_wait!(
      service: shared.parent_service, kind: "service.export",
      params: { service_type: "postgres", database: shared.shared_db_name, presigned_put_url: put_url }
    )

    get_url = destination.s3_presigned_url(key)
    Services::Ops.issue_and_wait!(
      service: dedicated, kind: "service.import",
      params: { service_type: "postgres", database: dedicated.name, presigned_get_url: get_url }
    )
  end

  def cutover!(dedicated:, shared:, app:)
    # Op-created services carry their own control-plane-composed DSN
    # (set by provision_existing! above).
    new_url = dedicated.dsn.presence || raise(UpgradeError::CutoverFailed, "no DSN on dedicated row")
    Apps::EnvWriter.set(app, { ENV_KEY => new_url })
    AppDatabase.where(app_record: app, database_service: shared, alias_name: "DATABASE").destroy_all
    AppDatabase.create!(app_record: app, database_service: dedicated, alias_name: "DATABASE")
    # Converge-rotate blocks until the new tasks serve — the old dokku
    # ps:report health poll is dead (every app is Swarm-run).
    Apps::Restarter.restart(app)
  end

  def rollback!(dedicated, shared, app, error, original_url)
    status_at_failure = dedicated.status

    begin
      if status_at_failure == "upgrading_cutover"
        shared_url = original_url.presence || shared.dsn.presence ||
                     raise(UpgradeError::RollbackFailed, "no shared #{ENV_KEY} to restore")
        Apps::EnvWriter.set(app, { ENV_KEY => shared_url })
        AppDatabase.where(app_record: app, alias_name: "DATABASE").destroy_all
        AppDatabase.create!(app_record: app, database_service: shared, alias_name: "DATABASE")
        Apps::Restarter.restart(app)
      end

      begin
        Services::Ops.issue_and_wait!(service: dedicated, kind: "service.destroy", params: { force: true })
      rescue StandardError => destroy_err
        Rails.logger.warn "Upgrade rollback: wokkud destroy failed (may never have been created): #{destroy_err.message}"
      end
      dedicated.destroy!
      shared.update!(status: :running) if shared.status != "running"

      Activity.log(
        user: app.creator,
        team: app.team,
        action: "addons.upgrade_to_dedicated.rolled_back",
        target: app,
        metadata: { failure: error.class.name, message: error.message, at_step: status_at_failure }
      )
    rescue => rollback_err
      dedicated.update!(status: :upgrading_failed) rescue nil
      Sentry.capture_exception(rollback_err, extra: { original: error.message, dedicated_id: dedicated.id }) if defined?(Sentry)
      raise UpgradeError::RollbackFailed, "rollback after #{error.class}: #{rollback_err.class}: #{rollback_err.message}"
    end
  end
end
