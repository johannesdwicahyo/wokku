class EnableSslJob < ApplicationJob
  queue_as :default

  # Async wrapper for `dokku letsencrypt:enable`. Cert issuance routinely
  # takes 30–60s (HTTP-01 challenge round-trip plus the request to Let's
  # Encrypt's ACME endpoint), well past kamal-proxy's 30s response cap.
  # Synchronous calls used to gateway-time-out and leave the user
  # unsure whether SSL was enabled. Async + Solid Queue gives clean UX
  # and keeps the dashboard request fast.
  def perform(domain_id)
    domain = Domain.find_by(id: domain_id)
    return unless domain
    app = domain.app_record
    return unless app

    success = false
    error_message = nil
    begin
      client = Dokku::Client.new(app.server)
      Dokku::Domains.new(client).enable_ssl(app.name)
      domain.update!(ssl_enabled: true, pending_action: nil)
      domain.create_certificate!(auto_renew: true, expires_at: 90.days.from_now) unless domain.certificate
      success = true
    rescue Dokku::Client::CommandError, Dokku::Client::ConnectionError => e
      error_message = e.message.to_s.lines.first&.strip || e.class.name
      Rails.logger.warn("EnableSslJob failed for domain #{domain_id}: #{error_message}")
      domain.update(pending_action: nil)
    end

    if success
      Activity.log(
        user: app.creator, team: app.team, action: "domain.ssl_enabled",
        target: domain, metadata: { app: app.name, hostname: domain.hostname }
      ) rescue nil
      app.broadcast_action_toast(level: "success", message: "SSL enabled for #{domain.hostname}.")
    else
      app.broadcast_action_toast(level: "error", message: "SSL failed for #{domain.hostname} — #{error_message}")
    end
  end
end
