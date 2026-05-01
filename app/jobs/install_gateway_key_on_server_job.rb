# Runs after a Server is created. Installs the wokku gateway's public key
# on the Dokku host as `dokku ssh-keys:add wokku-gateway <pubkey>`, so
# the gateway's proxied git pushes (ssh dokku@<server>) are accepted.
#
# The actual private half of the gateway key lives in wokku.cloud's
# .kamal/secrets and is mounted as WOKKU_GATEWAY_SSH_PUBLIC_KEY in the
# web container's env. If it isn't configured, this job logs + no-ops;
# dev/test environments don't need a real gateway.
class InstallGatewayKeyOnServerJob < ApplicationJob
  queue_as :default

  GATEWAY_NAME = "wokku-gateway".freeze

  # `name` and `pubkey` are overridable so rotation can stage a replacement
  # key under a temporary alias (e.g. "wokku-gateway-next") alongside the
  # current one, then swap.
  def perform(server_id, name = GATEWAY_NAME, pubkey = nil)
    server = Server.find_by(id: server_id)
    return unless server

    pubkey = (pubkey || ENV["WOKKU_GATEWAY_SSH_PUBLIC_KEY"]).to_s.strip
    if pubkey.blank?
      Rails.logger.warn("InstallGatewayKeyOnServerJob: no pubkey available — skipping for server=#{server.id}")
      return
    end

    client = Dokku::Client.new(server)
    ssh_keys = Dokku::SshKeys.new(client)
    ssh_keys.add(name, pubkey)
    Rails.logger.info("InstallGatewayKeyOnServerJob: installed '#{name}' on #{server.name}")
  rescue Dokku::Client::ConnectionError, Dokku::Client::CommandError => e
    Rails.logger.error("InstallGatewayKeyOnServerJob: #{e.class}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end
end
