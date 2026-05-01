class GrantAppAclJob < ApplicationJob
  queue_as :default

  # Grant all of a user's SSH keys ACL access to a specific app
  def perform(app_record_id, user_id)
    app = AppRecord.find_by(id: app_record_id)
    user = User.find_by(id: user_id)
    return unless app && user

    client = Dokku::Client.new(app.server)
    acl = Dokku::Acl.new(client)

    user.ssh_public_keys.each do |key|
      key_name = "wokku-user-#{user.id}-key-#{key.id}"
      acl.add(app.name, key_name)
    rescue Dokku::Client::CommandError => e
      Rails.logger.warn("GrantAppAclJob: Failed ACL for #{key_name} on #{app.name}: #{e.message}")
    end
  rescue => e
    Rails.logger.warn("GrantAppAclJob: Failed for app #{app_record_id}: #{e.message}")
  end
end
