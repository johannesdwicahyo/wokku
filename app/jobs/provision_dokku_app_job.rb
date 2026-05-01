class ProvisionDokkuAppJob < ApplicationJob
  queue_as :default

  # Creates the Dokku-side app shell (`dokku apps:create <name>`) so
  # that addons attached before the first `git push` can link cleanly.
  #
  # Idempotent — Dokku's apps:create returns non-zero with "App already
  # exists" if the app is there, so we check first via apps:list. The
  # AppRecord stays in :created status either way; the user's first
  # push flips it to :running.
  def perform(app_record_id)
    app = AppRecord.find_by(id: app_record_id)
    return unless app

    client = Dokku::Client.new(app.server)
    apps   = Dokku::Apps.new(client)

    return if apps.list.include?(app.name)

    apps.create(app.name)
  rescue Dokku::Client::CommandError, Dokku::Client::ConnectionError => e
    # Don't fail the AppRecord creation — the app row exists in our DB,
    # the Dokku-side shell will be auto-created by `git push` anyway.
    # Log so we notice if this happens often.
    Rails.logger.warn("ProvisionDokkuAppJob failed for #{app.name}: #{e.message}")
    Sentry.capture_exception(e, extra: { app_id: app_record_id, app_name: app.name }) if defined?(Sentry)
  end
end
