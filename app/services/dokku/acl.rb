require "shellwords"

module Dokku
  class Acl
    def initialize(client)
      @client = client
    end

    # Grant a user access to push to an app
    # ssh_key_name: the name used in ssh-keys:add (e.g., "user-42")
    # app_name: the Dokku app name
    def add(app_name, ssh_key_name)
      @client.run("acl:add #{Shellwords.escape(app_name)} #{Shellwords.escape(ssh_key_name)}")
    end

    # Revoke a user's access to an app
    def remove(app_name, ssh_key_name)
      @client.run("acl:remove #{Shellwords.escape(app_name)} #{Shellwords.escape(ssh_key_name)}")
    end

    # List users with access to an app
    def list(app_name)
      output = @client.run("acl:list #{Shellwords.escape(app_name)}")
      output.lines.map(&:strip).reject(&:empty?)
    end

    # Grant a user access to all apps owned by their team on this server
    def grant_team_apps(ssh_key_name, app_records)
      app_records.each do |app|
        add(app.name, ssh_key_name)
      rescue Dokku::Client::CommandError => e
        Rails.logger.warn("Dokku::Acl: Failed to add #{ssh_key_name} to #{app.name}: #{e.message}")
      end
    end

    # Revoke a user's access to all apps on this server
    def revoke_all(ssh_key_name, app_records)
      app_records.each do |app|
        remove(app.name, ssh_key_name)
      rescue Dokku::Client::CommandError => e
        Rails.logger.warn("Dokku::Acl: Failed to remove #{ssh_key_name} from #{app.name}: #{e.message}")
      end
    end
  end
end
