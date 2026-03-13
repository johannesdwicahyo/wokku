class WakeAppJob < ApplicationJob
  queue_as :default

  def perform(app_record_id)
    app = AppRecord.find_by(id: app_record_id)
    return unless app&.sleeping?

    client = Dokku::Client.new(app.server)
    Dokku::Processes.new(client).start(app.name)
    app.running!
  rescue Dokku::Client::ConnectionError, Dokku::Client::CommandError => e
    Rails.logger.error("WakeAppJob: Failed to wake #{app&.name}: #{e.message}")
  end
end
