require "shellwords"

# Provisions a fresh dedicated database container for engines that have
# no shared variant (MySQL, Mongo). Bundle v2 REVISED 2026-05-31:
# DatabaseServiceUpgrade routes here for these engines instead of the
# Pg/Redis migration jobs.
#
# Five-step state machine (no migration, no shared cleanup):
#   1. provision dedicated container
#   2. set <ENGINE>_URL on the app
#   3. link AppDatabase row with the right alias
#   4. restart app + health-check
#   5. mark dedicated row :running
#
# Retries OFF — half-provisioned container shouldn't replay automatically.
class CreateDedicatedDatabaseJob < ApplicationJob
  queue_as :default
  retry_on StandardError, attempts: 1

  HEALTH_POLL_INTERVAL = 5
  HEALTH_POLL_MAX_WAIT = 60

  # Per-engine: alias name in AppDatabase + env var the app reads.
  ENGINE_CONFIG = {
    "mysql"   => { alias_name: "DATABASE", env: "DATABASE_URL" },
    "mongodb" => { alias_name: "DATABASE", env: "DATABASE_URL" }
  }.freeze

  def perform(dedicated_db_id)
    dedicated = DatabaseService.find(dedicated_db_id)
    app       = first_app_for_dedicated(dedicated)
    client    = Dokku::Client.new(dedicated.server)
    config    = ENGINE_CONFIG.fetch(dedicated.service_type)

    begin
      provision!(client, dedicated)
      dedicated.update!(status: :upgrading_cutover)

      cutover!(client, dedicated: dedicated, app: app, config: config)
      wait_for_healthy_restart!(client, app)

      dedicated.update!(status: :running)

      Activity.log(
        user: app.creator, team: app.team,
        action: "addons.dedicated_db.created",
        target: app,
        metadata: { engine: dedicated.service_type, dedicated_id: dedicated.id }
      )
    rescue => e
      rollback!(client, dedicated, e)
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

  def provision!(client, dedicated)
    Dokku::Databases.new(client).create(dedicated.service_type, dedicated.name)
    Dokku::DatabaseResources.new(client).apply(dedicated)
  end

  def cutover!(client, dedicated:, app:, config:)
    info = Dokku::Databases.new(client).info(dedicated.service_type, dedicated.name)
    new_url = info["dsn"] || info["internal_url"] ||
              raise(UpgradeError::ProvisioningFailed, "no DSN in #{dedicated.service_type}:info")
    Dokku::Config.new(client).set(app.name, { config[:env] => new_url })
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

  def rollback!(client, dedicated, error)
    Dokku::Databases.new(client).destroy(dedicated.service_type, dedicated.name) rescue nil
    dedicated.destroy!
    Sentry.capture_exception(error, extra: { dedicated_id: dedicated.id }) if defined?(Sentry)
  end
end
