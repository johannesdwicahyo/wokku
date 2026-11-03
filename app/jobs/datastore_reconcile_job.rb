# Supervision sweep: ensures every wokkud-managed datastore that owns a
# container (the shared-postgres parent + every dedicated service) still has
# a live container, recreating a REMOVED one from its intact data via the
# service.ensure op. Also reconciles DatabaseService#status against reality —
# the 2026-07-21 incident had a row reading :running while the container was
# gone. Shared tenants are skipped: a tenant is a role+DB inside the parent,
# so ensuring the parent restores it.
#
# Runs every 3 min. Steady state is an existence-check per service (ensure
# no-ops on a live container). Credentials never leave the container (the
# databasement boundary): ensure recreates from data + run-spec only — this
# job never reads, stores, or logs a DB password.
class DatastoreReconcileJob < ApplicationJob
  queue_as :health

  ENSURE_TIMEOUT = 120

  def perform
    container_owning_services.find_each do |db|
      reconcile_one(db)
    rescue Services::Ops::Failed => e
      handle_failure(db, e)
    rescue Services::Ops::Timeout, StandardError => e
      # Transient (docker/host/network): DO NOT flip status on an unknown
      # observation — a blip must never mass-mark services crashed.
      Rails.logger.warn("DatastoreReconcileJob: #{db.name} ensure transient: #{e.class} #{e.message}")
      Sentry.capture_exception(e, extra: { database_service: db.name }) if defined?(Sentry)
    end
  end

  private

  # Services this phase can ensure: every DEDICATED service (its engine is in
  # wokkud's dedicatedEngines) PLUS the one shared parent wokkud has baked-in
  # constants for (dokku-shared-postgres, dokku-shared-mariadb). Excluded:
  #   - shared TENANTS (tier "shared_free") — a role+DB inside the parent, no
  #     own container; the parent's ensure covers them.
  #   - OTHER shared parents (tier "shared_host", e.g. shared-memcached/minio) —
  #     also wokkud_managed but service.ensure has no recreate branch for them
  #     (not in dedicatedEngines, no baked-in path). Supervising them is a
  #     follow-up (each needs its own ensure branch); ensuring them now would
  #     fail every sweep. Excluding is explicit; a silent false-success is worse.
  #   - engines wokkud can't run (no DEFAULT_IMAGES entry) — ensure raises
  #     ArgumentError for them on every sweep (2026-10-19: ~100 Sentry
  #     events/day from mysql, before wokkud ran mysql), and nothing could
  #     recreate them anyway.
  # (tier_name is NOT NULL DEFAULT 'basic', so the NOT IN clause is exact.)
  def container_owning_services
    DatabaseService.where(wokkud_managed: true, service_type: DatabaseProvisioner::DEFAULT_IMAGES.keys)
                   .where("tier_name NOT IN (?) OR name IN (?)",
                          %w[shared_free shared_host], DatabaseProvisioner::SHARED_PARENTS.values)
  end

  def reconcile_one(db)
    op = Services::Ops.issue_and_wait!(service: db, kind: "service.ensure",
                                       params: ensure_params(db), timeout: ENSURE_TIMEOUT)
    log_recreate(db) if op.respond_to?(:result) && op.result&.dig("action") == "recreated"
    # Success = the service is up (already-present or recreated). Reconcile a
    # stale non-running status confidently. update! (not update_column) so
    # the after_update_commit broadcast fires — a truth-reconciling job that
    # doesn't refresh the dashboard is self-defeating.
    db.update!(status: :running) if db.status.to_s != "running"
  end

  # A recreate means the container was gone and got rebuilt from intact data
  # — a real event operators must see (a repeated one is a crash-loop). No
  # dashboard-visible signal existed for this before; log + Sentry breadcrumb
  # match the pattern already used elsewhere in this job.
  def log_recreate(db)
    Rails.logger.warn("DatastoreReconcileJob: recreated #{db.name} (was removed; rebuilt on intact data)")
    Sentry.capture_message("datastore #{db.name} recreated by DatastoreReconcileJob", level: :info) if defined?(Sentry)
  end

  def handle_failure(db, err)
    if err.op&.error_code == "data_dir_missing"
      # Container gone AND data absent — a real outage needing restore. Make
      # the dashboard tell the truth (status + reason) and alert. update!
      # (not update_column) so the after_update_commit broadcast fires.
      # (DatabaseService has no :crashed enum — that is AppRecord's; :error
      # is its failure state.)
      if db.status.to_s != "error"
        db.update!(status: :error,
                   last_error: "container gone, data dir missing — needs restore (#{Time.current.utc.iso8601})")
      end
      Rails.logger.error("DatastoreReconcileJob: #{db.name} data_dir_missing — needs restore")
      Sentry.capture_message("datastore #{db.name} data_dir_missing", level: :error) if defined?(Sentry)
    else
      Rails.logger.warn("DatastoreReconcileJob: #{db.name} ensure failed: #{err.message}")
      Sentry.capture_exception(err, extra: { database_service: db.name }) if defined?(Sentry)
    end
  end

  # Params for service.ensure. The shared parent needs none (wokkud supplies
  # its baked-in path/image/alias); a dedicated service reuses the same run-spec
  # DatabaseProvisioner assembles for service.create.
  def ensure_params(db)
    return {} if DatabaseProvisioner::SHARED_PARENTS.value?(db.name) # shared parent
    DatabaseProvisioner.ensure_params_for(db)
  end
end
