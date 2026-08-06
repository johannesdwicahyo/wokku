class CreateAddonJob < ApplicationJob
  queue_as :default

  # Provisions a dedicated database/service add-on and links it to the
  # chosen app via the canonical DatabaseProvisioner ops stanza
  # (service.create op + DSN + EnvWriter env write + AppDatabase row).
  # Async so HTTP requests don't time out while the agent pulls a
  # multi-MB Docker image (kamal-proxy default is 30s).
  #
  # On failure the row is kept in :error with last_error so the dashboard
  # shows the red card with Retry / Destroy.
  def perform(database_service_id, app_id)
    db = DatabaseService.find_by(id: database_service_id)
    return unless db
    app = AppRecord.find_by(id: app_id)
    return unless app

    # The controller already created the row (sync validation + name-slot
    # sweep + stable id for the addon page), so provision it in place.
    DatabaseProvisioner
      .new(app: app, service_type: db.service_type, tier: db.tier_name, name: db.name, creator: db.creator)
      .provision_existing!(db)
    db.update!(status: :running)

    # dokku's `<plugin>:link` restarted the app so the new env took effect —
    # converge is the wokkud equivalent. Best-effort: provisioning succeeded.
    begin
      Apps::Restarter.restart(app)
    rescue => e
      Rails.logger.warn("CreateAddonJob: restart after link failed for #{app.name}: #{e.message}")
    end

    notify_complete(db, app)
  rescue => e
    Rails.logger.warn("CreateAddonJob: #{db&.name} failed: #{e.message}")
    # Don't destroy the row — surface the failure in the dashboard so
    # the user can see what went wrong (often actionable: unsupported
    # engine, agent offline, etc.) and choose to Retry or Destroy.
    # broadcast_status_change fires automatically via after_update_commit
    # so the addon card flips to its red error state in place.
    db&.update(status: :error, last_error: e.message.to_s.truncate(2000))
    notify_failed(db, app, e.message)
  end

  private

  def notify_complete(db, app)
    return unless defined?(Activity)
    creator = app.creator
    team = app.team
    return unless creator && team
    Activity.log(
      user: creator, team: team, action: "addon.created",
      target: db, metadata: { name: db.name, type: db.service_type, tier: db.tier_name, app: app.name }
    )
  rescue StandardError
    nil
  end

  def notify_failed(db, app, message)
    return unless defined?(Activity)
    creator = app.creator
    team = app.team
    return unless creator && team
    Activity.log(
      user: creator, team: team, action: "addon.create_failed",
      target: app, metadata: { name: db&.name, type: db&.service_type, error: message }
    )
  rescue StandardError
    nil
  end
end
