class CreateAddonJob < ApplicationJob
  queue_as :default

  # Creates a database/service add-on on the Dokku host and links it to
  # the chosen app. Async so HTTP requests don't time out when Dokku has
  # to pull a multi-MB Docker image first (memcached, elasticsearch,
  # rabbitmq, etc. — kamal-proxy default is 30s).
  #
  # Failure cleanup is intentional: if Dokku errors, we destroy the
  # DatabaseService row so the user can retry without a name collision.
  def perform(database_service_id, app_id)
    db = DatabaseService.find_by(id: database_service_id)
    return unless db
    app = AppRecord.find_by(id: app_id)
    return unless app

    client = Dokku::Client.new(db.server)
    Dokku::Databases.new(client).create(db.service_type, db.name)
    Dokku::Databases.new(client).link(db.service_type, db.name, app.name)

    db.app_databases.find_or_create_by!(app_record: app) do |ad|
      ad.alias_name = db.name
    end
    db.update!(status: :running)

    # Open the billing segment now that the addon is live and linked to
    # an app (the app's creator owns the meter). Free shared tenants
    # and zero-rate tiers skip this internally.
    db.open_billing_segment(user: app.creator, app_record: app) if app.creator

    ApplyDatabaseTierJob.perform_later(db.id) if db.tier_name.present? && !db.shared?

    notify_complete(db, app)
  rescue Dokku::Client::CommandError, Dokku::Client::ConnectionError => e
    Rails.logger.warn("CreateAddonJob: #{db&.name} failed: #{e.message}")
    db&.destroy
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
