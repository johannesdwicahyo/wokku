# Counterpart to InstallGatewayKeyOnServerJob: removes a named key from
# `dokku ssh-keys` on a Dokku host. Used during gateway key rotation.
class RemoveGatewayKeyFromServerJob < ApplicationJob
  queue_as :default

  def perform(server_id, name)
    server = Server.find_by(id: server_id)
    return unless server

    client = Dokku::Client.new(server)
    Dokku::SshKeys.new(client).remove(name)
    Rails.logger.info("RemoveGatewayKeyFromServerJob: removed '#{name}' from #{server.name}")
  rescue Dokku::Client::ConnectionError, Dokku::Client::CommandError => e
    Rails.logger.error("RemoveGatewayKeyFromServerJob: #{e.class}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end
end
