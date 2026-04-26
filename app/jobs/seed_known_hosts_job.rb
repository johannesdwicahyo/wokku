# Runs after a Server is created. ssh-keyscans the Dokku host and adds
# its key to the gateway's known_hosts file so subsequent ssh proxies
# can verify the host identity.
class SeedKnownHostsJob < ApplicationJob
  queue_as :default

  def perform(server_id)
    server = Server.find_by(id: server_id)
    return unless server

    line = Git::KnownHostsWriter.add(server)
    if line
      Rails.logger.info("SeedKnownHostsJob: added host key for #{server.name} (#{server.host})")
    else
      Rails.logger.warn("SeedKnownHostsJob: WOKKU_GATEWAY_KNOWN_HOSTS_PATH not set — skipping for server=#{server.id}")
    end
  rescue Git::KnownHostsWriter::Error => e
    Rails.logger.error("SeedKnownHostsJob: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end
end
