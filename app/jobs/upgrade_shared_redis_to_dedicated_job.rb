require "shellwords"

# Promotes a shared Redis tenant to a dedicated wokkud-managed redis
# container. Six-step state machine:
#   1. provision dedicated container (service.create op via DatabaseProvisioner)
#   2. export shared tenant (RESP pipe-format RESTORE commands)
#   3. import into dedicated via redis-cli --pipe
#   4. flip REDIS_URL + relink AppDatabase
#   5. restart app (converge waits — no separate health poll needed)
#   6. schedule DropSharedRedisTenantJob 24h out
#
# Step 2/3 stay a host-side docker pipe (Hosts::Ssh, root): wokkud's
# service.export for redis is a whole-parent RDB snapshot (wrong granularity
# for one tenant) and service.import REFUSES redis outright (an RDB restore
# means replacing the data file under a stopped server — not streamable), so
# the ops relay the pg job uses cannot carry a tenant migration. The pipe
# ports dokku-shared-redis's export loop (SCAN by ACL prefix → DUMP →
# RESTORE lines) verbatim, feeding redis-cli --pipe on the dedicated
# container — same semantics the plugin leg had.
#
# Retries are explicitly OFF — a half-migrated store must not be replayed.
# User retries via "Try again" button on the failed card.
class UpgradeSharedRedisToDedicatedJob < ApplicationJob
  queue_as :default
  retry_on StandardError, attempts: 1

  ENV_KEY = "REDIS_URL".freeze

  def perform(dedicated_db_id)
    dedicated = DatabaseService.find(dedicated_db_id)
    shared    = dedicated.upgrade_source
    app       = shared.app_records.first
    # Captured pre-cutover: rollback restores it, and the migration parses
    # the tenant's ACL user/password out of it (older shared rows predate
    # the dsn column).
    original_url = app.runtime_env[ENV_KEY]

    begin
      provision_container!(dedicated)
      dedicated.update!(status: :upgrading_migrating)

      migrate_data!(shared: shared, dedicated: dedicated, original_url: original_url)
      dedicated.update!(status: :upgrading_cutover)

      cutover!(dedicated: dedicated, shared: shared, app: app)

      dedicated.update!(status: :running)
      shared.update!(status: :pending_destroy, pending_destroy_at: 24.hours.from_now)
      DropSharedRedisTenantJob.set(wait: 24.hours).perform_later(shared.id)

      Activity.log(
        user: app.creator,
        team: app.team,
        action: "addons.upgrade_to_dedicated.completed",
        target: app,
        metadata: { shared_id: shared.id, dedicated_id: dedicated.id, engine: "redis" }
      )
    rescue => e
      rollback!(dedicated, shared, app, e, original_url)
      raise
    end
  end

  private

  # Same ops stanza as CreateAddonJob (service.create + CP-composed DSN).
  # app: nil — env flip + AppDatabase relink happen at cutover.
  def provision_container!(dedicated)
    DatabaseProvisioner
      .new(app: nil, service_type: dedicated.service_type, tier: dedicated.tier_name,
           name: dedicated.name, server: dedicated.server, creator: dedicated.creator)
      .provision_existing!(dedicated)
  end

  def migrate_data!(shared:, dedicated:, original_url:)
    tenant_url = shared.dsn.presence || original_url.presence ||
                 raise(UpgradeError::MigrationFailed, "no shared #{ENV_KEY} to read tenant credentials from")
    tenant = URI.parse(tenant_url)
    dedicated_pass = URI.parse(dedicated.dsn.to_s).password.presence ||
                     raise(UpgradeError::MigrationFailed, "no DSN password on dedicated row")

    script = migration_script(
      parent_container: shared.parent_service.name,
      dedicated_container: "dokku.redis.#{dedicated.name}",
      user: tenant.user,
      password: tenant.password,
      dedicated_pass: dedicated_pass
    )
    Hosts::Ssh.new(dedicated.server).run_raw("bash -s", timeout: 600, stdin: script)
  end

  # dokku-shared-redis's service_export, docker-side: SCAN the tenant's ACL
  # key prefix as the tenant user, DUMP each key, and emit
  # `RESTORE <key> <pttl> <payload> REPLACE` lines piped straight into the
  # dedicated container's redis-cli --pipe (the plugin's import leg).
  def migration_script(parent_container:, dedicated_container:, user:, password:, dedicated_pass:)
    src = "docker exec #{Shellwords.escape(parent_container)} redis-cli " \
          "--user #{Shellwords.escape(user)} --pass #{Shellwords.escape(password)} --no-auth-warning"
    dst = "docker exec -i #{Shellwords.escape(dedicated_container)} redis-cli " \
          "-a #{Shellwords.escape(dedicated_pass)} --no-auth-warning --pipe"
    <<~BASH
      set -euo pipefail
      export_tenant() {
        cursor=0
        while :; do
          result="$(#{src} SCAN "$cursor" MATCH #{Shellwords.escape("#{user}:*")} COUNT 1000)"
          cursor="$(echo "$result" | head -1)"
          keys="$(echo "$result" | tail -n +2)"
          while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            pttl="$(#{src} PTTL "$key")"
            [[ "$pttl" == "-2" ]] && continue
            [[ "$pttl" == "-1" ]] && pttl=0
            payload="$(#{src} --no-raw DUMP "$key" | sed 's/^"\\(.*\\)"$/\\1/')"
            [[ -z "$payload" ]] && continue
            printf 'RESTORE "%s" %s "%s" REPLACE\\n' "$key" "$pttl" "$payload"
          done <<< "$keys"
          [[ "$cursor" == "0" ]] && break
        done
      }
      export_tenant | #{dst}
    BASH
  end

  def cutover!(dedicated:, shared:, app:)
    # Op-created services carry their own control-plane-composed DSN
    # (set by provision_existing! above).
    new_url = dedicated.dsn.presence || raise(UpgradeError::CutoverFailed, "no DSN on dedicated row")
    Apps::EnvWriter.set(app, { ENV_KEY => new_url })
    AppDatabase.where(app_record: app, database_service: shared, alias_name: "REDIS").destroy_all
    AppDatabase.create!(app_record: app, database_service: dedicated, alias_name: "REDIS")
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
        AppDatabase.where(app_record: app, alias_name: "REDIS").destroy_all
        AppDatabase.create!(app_record: app, database_service: shared, alias_name: "REDIS")
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
        metadata: { failure: error.class.name, message: error.message, at_step: status_at_failure, engine: "redis" }
      )
    rescue => rollback_err
      dedicated.update!(status: :upgrading_failed) rescue nil
      Sentry.capture_exception(rollback_err, extra: { original: error.message, dedicated_id: dedicated.id }) if defined?(Sentry)
      raise UpgradeError::RollbackFailed, "rollback after #{error.class}: #{rollback_err.class}: #{rollback_err.message}"
    end
  end
end
