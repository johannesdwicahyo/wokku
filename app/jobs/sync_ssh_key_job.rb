class SyncSshKeyJob < ApplicationJob
  queue_as :default

  # Syncs a user's SSH key to all servers in their team,
  # and sets ACLs so they can only push to their own apps.
  #
  # action: :add or :remove
  # ssh_public_key_id: the specific key to sync
  def perform(ssh_public_key_id, user_id, action: :add)
    user = User.find_by(id: user_id)
    return unless user

    key_record = action.to_sym == :remove ? nil : SshPublicKey.find_by(id: ssh_public_key_id)
    return if action.to_sym == :add && key_record.nil?

    key_name = "wokku-user-#{user.id}-key-#{ssh_public_key_id}"
    team = user.teams.first
    return unless team

    team.servers.each do |server|
      sync_to_server(server, user, key_name, key_record, action, team)
    rescue => e
      Rails.logger.error("SyncSshKeyJob: Failed for user #{user.id} on #{server.name}: #{e.message}")
    end
  end

  private

  def sync_to_server(server, user, key_name, key_record, action, team)
    client = Dokku::Client.new(server)
    ssh_keys = Dokku::SshKeys.new(client)
    acl = Dokku::Acl.new(client)

    if action.to_sym == :add
      ssh_keys.add(key_name, key_record.public_key)

      # Grant access to all team apps on this server
      team_apps = server.app_records.where(team: team)
      acl.grant_team_apps(key_name, team_apps)

      Rails.logger.info("SyncSshKeyJob: Added #{key_name} to #{server.name}, ACL for #{team_apps.count} apps")
    else
      # Revoke all app access
      team_apps = server.app_records.where(team: team)
      acl.revoke_all(key_name, team_apps)

      # Remove the key
      ssh_keys.remove(key_name)

      Rails.logger.info("SyncSshKeyJob: Removed #{key_name} from #{server.name}")
    end
  end
end
