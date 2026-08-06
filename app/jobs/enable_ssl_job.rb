class EnableSslJob < ApplicationJob
  queue_as :default

  # Caddy owns TLS since the B1 router flip: managed subdomains are covered
  # by the wildcard cert shipped in the router config, custom domains get
  # on-demand ACME once DNS verifies (B6 W6). "Enabling" SSL is pure
  # control-plane bookkeeping — the only real precondition is verified DNS,
  # without which Caddy cannot complete the ACME challenge.
  def perform(domain_id)
    domain = Domain.find_by(id: domain_id)
    return unless domain
    app = domain.app_record
    return unless app

    unless domain.managed_subdomain? || domain.dns_verified?
      domain.update(pending_action: nil)
      app.broadcast_action_toast(level: "error", message: "SSL failed for #{domain.hostname} — DNS is not verified yet. Point your domain at the server first.")
      return
    end

    domain.update!(ssl_enabled: true, pending_action: nil)
    if domain.certificate.nil?
      if domain.managed_subdomain? && (cert = WildcardCertificate.current)
        domain.create_certificate!(auto_renew: false, expires_at: cert.expires_at)
      else
        domain.create_certificate!(auto_renew: true, expires_at: 90.days.from_now)
      end
    end

    Activity.log(
      user: app.creator, team: app.team, action: "domain.ssl_enabled",
      target: domain, metadata: { app: app.name, hostname: domain.hostname }
    ) rescue nil
    app.broadcast_action_toast(level: "success", message: "SSL enabled for #{domain.hostname}.")
  end
end
