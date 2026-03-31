class SyncServerJob < ApplicationJob
  queue_as :default

  def perform(server_id)
    server = Server.find(server_id)
    server.update_column(:status, Server.statuses[:syncing])

    client = Dokku::Client.new(server)
    dokku_apps = Dokku::Apps.new(client)
    dokku_domains = Dokku::Domains.new(client)

    remote_app_names = dokku_apps.list
    local_app_names = server.app_records.pluck(:name)

    (remote_app_names - local_app_names).each do |name|
      app = server.app_records.create!(
        name: name,
        team: server.team,
        creator: server.team.owner
      )
      Activity.log(user: server.team.owner, team: server.team, action: "app.created", target: app, metadata: { source: "sync" }) rescue nil
    end

    (local_app_names - remote_app_names).each do |name|
      server.app_records.find_by(name: name)&.destroy
    end

    # Sync domains for each app
    server.app_records.reload.each do |app_record|
      sync_domains(dokku_domains, app_record)
    end

    # Sync databases
    dokku_databases = Dokku::Databases.new(client)
    sync_databases(dokku_databases, server)

    # Sync database-to-app links
    sync_database_links(dokku_databases, server)

    server.app_records.update_all(synced_at: Time.current)
    server.update_column(:status, Server.statuses[:connected])
  rescue Dokku::Client::ConnectionError
    server.update_column(:status, Server.statuses[:unreachable])
  end

  private

  def sync_domains(dokku_domains, app_record)
    remote_hostnames = dokku_domains.list(app_record.name)
    local_hostnames = app_record.domains.pluck(:hostname)

    (remote_hostnames - local_hostnames).each do |hostname|
      app_record.domains.create!(hostname: hostname)
    end

    (local_hostnames - remote_hostnames).each do |hostname|
      app_record.domains.find_by(hostname: hostname)&.destroy
    end
  rescue => e
    Rails.logger.warn "Failed to sync domains for #{app_record.name}: #{e.message}"
  end

  def sync_database_links(dokku_databases, server)
    server.database_services.find_each do |db|
      info = dokku_databases.info(db.service_type, db.name)
      links_value = info["links"] || info["Links"] || ""
      remote_app_names = links_value.split(/[\s,]+/).reject(&:blank?)

      local_app_names = db.app_records.pluck(:name)

      # Add missing links
      (remote_app_names - local_app_names).each do |app_name|
        app = server.app_records.find_by(name: app_name)
        next unless app
        db.app_databases.find_or_create_by!(app_record: app) do |ad|
          ad.alias_name = db.service_type.upcase
        end
      end

      # Remove stale links
      (local_app_names - remote_app_names).each do |app_name|
        app = server.app_records.find_by(name: app_name)
        db.app_databases.where(app_record: app).destroy_all if app
      end
    end
  rescue => e
    Rails.logger.warn "Failed to sync database links for server #{server.name}: #{e.message}"
  end

  def sync_databases(dokku_databases, server)
    Dokku::Databases::SUPPORTED_TYPES.each do |service_type|
      remote_names = dokku_databases.list(service_type)
      local_names = server.database_services.where(service_type: service_type).pluck(:name)

      (remote_names - local_names).each do |name|
        server.database_services.create!(name: name, service_type: service_type, status: :running)
      end

      (local_names - remote_names).each do |name|
        server.database_services.find_by(name: name, service_type: service_type)&.destroy
      end
    end
  rescue => e
    Rails.logger.warn "Failed to sync databases for server #{server.name}: #{e.message}"
  end
end
