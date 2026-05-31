require "shellwords"

# Promotes a shared Redis tenant to a dedicated dokku-redis container.
# Six-step state machine:
#   1. provision dedicated container
#   2. export shared tenant (RESP pipe-format RESTORE commands)
#   3. import into dedicated via docker exec redis-cli --pipe
#   4. flip REDIS_URL + relink AppDatabase
#   5. restart app + health-check
#   6. schedule DropSharedRedisTenantJob 24h out
#
# Retries are explicitly OFF — a half-migrated store must not be replayed.
# User retries via "Try again" button on the failed card.
#
# Mirrors UpgradeSharedPgToDedicatedJob — see that file for rationale.
class UpgradeSharedRedisToDedicatedJob < ApplicationJob
  queue_as :default
  retry_on StandardError, attempts: 1

  HEALTH_POLL_INTERVAL = 5
  HEALTH_POLL_MAX_WAIT = 60

  def perform(dedicated_db_id)
    dedicated = DatabaseService.find(dedicated_db_id)
    shared    = dedicated.upgrade_source
    app       = shared.app_records.first
    client    = Dokku::Client.new(dedicated.server)

    begin
      provision_container!(client, dedicated)
      dedicated.update!(status: :upgrading_migrating)

      migrate_data!(client, shared: shared, dedicated: dedicated)
      dedicated.update!(status: :upgrading_cutover)

      cutover!(client, dedicated: dedicated, shared: shared, app: app)
      wait_for_healthy_restart!(client, app)

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
      rollback!(client, dedicated, shared, app, e)
      raise
    end
  end

  private

  def provision_container!(client, dedicated)
    Dokku::Databases.new(client).create("redis", dedicated.name)
    Dokku::DatabaseResources.new(client).apply(dedicated)
  end

  # Pipes the shared-redis export directly into the dedicated container's
  # redis-cli via --pipe. The dedicated container name follows Dokku's
  # convention: dokku.redis.<service-name>.
  def migrate_data!(client, shared:, dedicated:)
    shared_slug = shared.shared_role_name.to_s.sub(/_role\z/, "")
    container   = "dokku.redis.#{dedicated.name}"
    cmd = "sh -c 'dokku shared-redis:export #{Shellwords.escape(shared_slug)} | docker exec -i #{Shellwords.escape(container)} redis-cli --pipe'"
    client.run(cmd, timeout: 600)
  end

  def cutover!(client, dedicated:, shared:, app:)
    info    = Dokku::Databases.new(client).info("redis", dedicated.name)
    new_url = info["dsn"] || info["internal_url"] || raise(UpgradeError::CutoverFailed, "no DSN in redis:info")
    Dokku::Config.new(client).set(app.name, { "REDIS_URL" => new_url })
    AppDatabase.where(app_record: app, database_service: shared, alias_name: "REDIS").destroy_all
    AppDatabase.create!(app_record: app, database_service: dedicated, alias_name: "REDIS")
    Dokku::Processes.new(client).restart(app.name)
  end

  def wait_for_healthy_restart!(client, app)
    deadline = Time.current + HEALTH_POLL_MAX_WAIT
    loop do
      out = client.run("ps:report #{Shellwords.escape(app.name)}", timeout: 30)
      return if out.match?(/Status:\s*running/i)
      raise UpgradeError::CutoverFailed if Time.current > deadline
      sleep HEALTH_POLL_INTERVAL
    end
  end

  def rollback!(client, dedicated, shared, app, error)
    status_at_failure = dedicated.status

    begin
      if status_at_failure == "upgrading_cutover"
        shared_url = lookup_shared_url(client, shared)
        Dokku::Config.new(client).set(app.name, { "REDIS_URL" => shared_url })
        AppDatabase.where(app_record: app, alias_name: "REDIS").destroy_all
        AppDatabase.create!(app_record: app, database_service: shared, alias_name: "REDIS")
        Dokku::Processes.new(client).restart(app.name)
      end

      Dokku::Databases.new(client).destroy("redis", dedicated.name) rescue nil
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

  def lookup_shared_url(client, shared)
    slug = shared.shared_role_name.to_s.sub(/_role\z/, "")
    info = Dokku::SharedRedis.new(client).info(slug)
    info[:connection_url] || raise(UpgradeError::RollbackFailed, "no connection_url in shared-redis:info")
  end
end
