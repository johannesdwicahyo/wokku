# Sweeper for unattached dedicated DatabaseService rows.
#
# After Dashboard::AppsController#destroy now tears down exclusively-linked
# databases (commit e1fa9ac), the only ways a dedicated DB can survive its
# parent app are: a Dokku error during destroy, a console-driven app delete
# that bypassed the controller, or a pre-fix orphan still on disk. This
# sweeper catches all three and stops the daily debit.
#
# Filters:
#   - dedicated only — shared tenants live as logical roles inside a shared
#     host container and are managed by SharedDatabaseQuotaJob.
#   - no app_databases join rows — the DB is unattached.
#   - older than the grace period — avoids racing with create flows where the
#     app record is created before the join row.
#
# Action: db.destroy. Under Phase 4 invoice billing the cost is bundled into
# the user's plan invoice — no per-database segment teardown is needed. The
# DatabaseService model has no Dokku-side teardown hook; that is the
# controller's job. We do attempt the Dokku destroy here too so the
# container goes away on the host.
class OrphanDatabaseSweepJob < ApplicationJob
  queue_as :default

  GRACE_PERIOD = 1.day

  def perform
    candidates = DatabaseService.dedicated
      .where.missing(:app_databases)
      .where("database_services.created_at < ?", GRACE_PERIOD.ago)

    candidates.find_each do |db|
      Rails.logger.warn(
        "OrphanDatabaseSweepJob: destroying unattached #{db.service_type} " \
        "service #{db.name} on #{db.server&.host} (age=#{(Time.current - db.created_at).to_i}s)"
      )

      tear_down_dokku_service(db)
      db.destroy
    rescue StandardError => e
      Rails.logger.error("OrphanDatabaseSweepJob: failed on #{db.name}: #{e.class}: #{e.message}")
      Sentry.capture_exception(e, extra: { service: db.name, type: db.service_type, server: db.server&.host }) if defined?(Sentry)
    end
  end

  private

  def tear_down_dokku_service(db)
    return unless db.server
    client = Dokku::Client.new(db.server)
    Dokku::Databases.new(client).destroy(db.service_type, db.name)
  rescue Dokku::Client::CommandError, Dokku::Client::ConnectionError => e
    # Either the Dokku service is already gone (orphan was disk-only) or
    # the host is unreachable. Either way we still close the billing
    # segment by destroying the DatabaseService record.
    Rails.logger.warn("OrphanDatabaseSweepJob: Dokku destroy failed for #{db.name}: #{e.message}")
  end
end
