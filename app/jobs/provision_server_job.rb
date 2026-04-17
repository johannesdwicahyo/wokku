class ProvisionServerJob < ApplicationJob
  queue_as :default

  DOKKU_INSTALL = "wget -NqO- https://dokku.com/bootstrap.sh | sudo DOKKU_TAG=v0.37.2 bash"
  MAX_WAIT = 120 # seconds to wait for server to boot

  def perform(server_id:, cloud_credential_id:, cloud_server_id:)
    server = Server.find(server_id)
    credential = CloudCredential.find(cloud_credential_id)

    provider = CloudProviders.const_get(credential.provider.capitalize).new(credential)

    # Wait for server to be ready
    server.update!(status: :syncing)
    waited = 0
    loop do
      status = provider.server_status(cloud_server_id)
      break if status == "running" || status == "active"
      sleep 5
      waited += 5
      raise "Server did not start within #{MAX_WAIT}s" if waited > MAX_WAIT
    end

    # Wait a bit more for SSH to be available
    sleep 10

    # Install Dokku via SSH
    ssh_options = { port: 22, non_interactive: true, timeout: 15 }
    ssh_options[:key_data] = [ server.ssh_private_key ] if server.ssh_private_key.present?

    Net::SSH.start(server.host, "root", ssh_options) do |ssh|
      # Install Dokku (takes 2-5 minutes)
      output = ""
      channel = ssh.open_channel do |ch|
        ch.exec(DOKKU_INSTALL) do |_ch, success|
          raise "Failed to start Dokku installation" unless success
          ch.on_data { |_, data| output << data }
          ch.on_extended_data { |_, _, data| output << data }
        end
      end
      channel.wait

      # Set global domain
      ssh.exec!("dokku domains:set-global #{server.name}.wokku.cloud") rescue nil

      # Install common plugins
      ssh.exec!("dokku plugin:install https://github.com/dokku/dokku-postgres.git") rescue nil
      ssh.exec!("dokku plugin:install https://github.com/dokku/dokku-redis.git") rescue nil
      ssh.exec!("dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git") rescue nil
    end

    server.update!(status: :connected)
    Rails.logger.info("ProvisionServerJob: #{server.name} provisioned and Dokku installed")

  rescue => e
    server.update!(status: :unreachable)
    Rails.logger.error("ProvisionServerJob: Failed to provision #{server.name}: #{e.message}")
  end
end
