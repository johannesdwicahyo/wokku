class LogStreamJob < ApplicationJob
  queue_as :logs

  def perform(app_id, channel_id)
    app = AppRecord.find_by(id: app_id)
    return unless app
    client = Dokku::Client.new(app.server)

    Timeout.timeout(30.minutes.to_i) do
      client.run_streaming("logs #{app.name} --tail") do |data|
        LogChannel.broadcast_to(app, { type: "log", data: data })
      end
    end
  rescue Timeout::Error
    LogChannel.broadcast_to(app, { type: "info", data: "Log stream timed out. Refresh to reconnect." })
  rescue Dokku::Client::ConnectionError => e
    LogChannel.broadcast_to(app, { type: "error", data: e.message })
  end
end
