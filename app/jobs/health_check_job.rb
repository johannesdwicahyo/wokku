class HealthCheckJob < ApplicationJob
  queue_as :default

  def perform(server_id)
    server = Server.find(server_id)
    client = Dokku::Client.new(server)

    if client.connected?
      server.update_column(:status, Server.statuses[:connected])
    else
      server.update_column(:status, Server.statuses[:unreachable])
    end
  rescue Dokku::Client::ConnectionError
    server.update_column(:status, Server.statuses[:unreachable])
  end
end
