class SslAutoRenewJob < ApplicationJob
  queue_as :default

  def perform
    Server.where(status: :connected).find_each do |server|
      client = Dokku::Client.new(server)
      client.run("letsencrypt:auto-renew")
      Rails.logger.info "SSL auto-renew completed for server #{server.name}"
    rescue => e
      Rails.logger.warn "SSL auto-renew failed for server #{server.name}: #{e.message}"
    end
  end
end
