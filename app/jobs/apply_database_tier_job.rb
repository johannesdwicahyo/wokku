class ApplyDatabaseTierJob < ApplicationJob
  queue_as :default

  # Apply a DatabaseService's selected tier to its running container via a
  # wokkud service.set_limits op (W7 Phase 2 — params contract proven in
  # B4, carried over from the retired dokku wrapper layer): the agent
  # does docker update --memory live and persists the engine's
  # max_connections.
  #
  # Skipped for shared tenants — those share the parent container's
  # resources and are governed by SharedDatabaseQuotaJob instead.
  def perform(database_service_id)
    db = DatabaseService.find_by(id: database_service_id)
    return unless db
    return if db.shared?

    if db.shape
      Services::Ops.issue_and_wait!(
        service: db, kind: "service.set_limits",
        params: { memory_mb: db.memory_mb, cpu: db.cpu.to_f, max_connections: db.max_connections_for_shape }
      )
      return
    end

    tier = db.service_tier
    return unless tier

    spec = tier.spec || {}
    memory_mb   = (spec["memory_mb"] || spec[:memory_mb]).to_i
    connections = (spec["connections"] || spec[:connections]).to_i
    return if memory_mb.zero? && connections.zero?

    Services::Ops.issue_and_wait!(
      service: db, kind: "service.set_limits",
      params: { memory_mb: memory_mb, max_connections: connections }
    )

    track_apply(db, tier)
  rescue Services::Ops::Failed, Services::Ops::Timeout => e
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
