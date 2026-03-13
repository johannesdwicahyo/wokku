class SyncServerJob < ApplicationJob
  queue_as :default

  def perform(server_id)
    server = Server.find(server_id)
    server.update_column(:status, Server.statuses[:syncing])

    client = Dokku::Client.new(server)
    dokku_apps = Dokku::Apps.new(client)

    remote_app_names = dokku_apps.list
    local_app_names = server.app_records.pluck(:name)

    (remote_app_names - local_app_names).each do |name|
      server.app_records.create!(
        name: name,
        team: server.team,
        creator: server.team.owner
      )
    end

    (local_app_names - remote_app_names).each do |name|
      server.app_records.find_by(name: name)&.destroy
    end

    server.app_records.update_all(synced_at: Time.current)
    server.update_column(:status, Server.statuses[:connected])
  rescue Dokku::Client::ConnectionError
    server.update_column(:status, Server.statuses[:unreachable])
  end
end
