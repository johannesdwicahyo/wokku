class ApplyDatabaseTierJob < ApplicationJob
  queue_as :default

  # Apply a DatabaseService's selected tier to its running container:
  #   - docker update --memory (live, no downtime)
  #   - ALTER SYSTEM max_connections (postgres) / mysql equiv
  #   - service restart so connection cap takes effect (~5s downtime)
  #
  # Skipped for shared tenants — those share the parent container's
  # resources and are governed by SharedDatabaseQuotaJob instead.
  def perform(database_service_id)
    db = DatabaseService.find_by(id: database_service_id)
    return unless db
    return if db.shared?

    tier = db.service_tier
    return unless tier

    spec = tier.spec || {}
    memory_mb   = spec["memory_mb"] || spec[:memory_mb]
    connections = spec["connections"] || spec[:connections]

    client = Dokku::Client.new(db.server)
    resources = Dokku::DatabaseResources.new(client)

    resources.apply_memory(db.service_type, db.name, memory_mb: memory_mb) if memory_mb
    resources.apply_max_connections(db.service_type, db.name, connections: connections) if connections

    # Restart only if max_connections changed (RAM change is live). Cheap to
    # always restart, but it's noisy — keep it conditional on a connections cap.
    resources.restart(db.service_type, db.name) if connections

    # Rotate the billing segment so the new hourly rate applies going
    # forward. Old segment closes at "now"; new segment opens at "now"
    # with the current tier's price.
    if (owner = db.app_records.first&.creator)
      db.rotate_billing_segment(user: owner)
    end

    track_apply(db, tier)
  rescue Dokku::Client::ConnectionError, Dokku::Client::CommandError => e
    Rails.logger.warn("ApplyDatabaseTierJob: failed for #{db&.name}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    raise
  end

  private

  def track_apply(db, tier)
    return unless defined?(Activity)
    creator = db.app_records.first&.creator
    team = db.app_records.first&.team
    return unless creator && team
    Activity.log(
      user: creator, team: team, action: "database.tier_changed",
      target: db, metadata: { tier: tier.name, service_type: db.service_type }
    )
  rescue StandardError => e
    Rails.logger.warn("ApplyDatabaseTierJob: activity log skipped: #{e.message}")
  end
end
