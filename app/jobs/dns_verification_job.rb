class DnsVerificationJob < ApplicationJob
  queue_as :health

  def perform(domain_id)
    domain = Domain.find_by(id: domain_id)
    return unless domain
    return unless dns_verified?(domain)

    # Auto-enable SSL on the first successful verification. Caddy owns TLS
    # (B6 W6): managed subdomains are covered by the wildcard cert in the
    # router config; custom domains flip to on-demand ACME on the next
    # router-config heartbeat once dns_verified is set.
    domain.update!(dns_verified: true, ssl_enabled: true)
  end

  private

  # A domain is considered verified if the DNS it resolves to matches
  # what the Dokku server serves. Two shapes are valid:
  #
  #   1. Subdomain with a CNAME to the app's canonical hostname
  #      (what `PostDeploySetupJob` creates via Cloudflare), e.g.
  #      `app.example.com` CNAME → `my-app.wokku.app` (canonical post-cutover;
  #      legacy `my-app.wokku.cloud` aliases are also accepted).
  #      The canonical domain is provided by `Wokku.config.canonical_domain`.
  #   2. Apex or any host with A/AAAA records that resolve to the
  #      Dokku server's public IP. DNS spec forbids CNAME on apex, so
  #      this is the only path for root domains like `example.com`.
  #
  # We don't require the CNAME target literally — we follow it to the
  # A record and compare IPs, so ALIAS/ANAME/flattening all work too.
  def dns_verified?(domain)
    server_ip = domain.app_record.server&.host.to_s
    return false if server_ip.blank?

    # A wildcard is proven by a random name under it resolving here.
    name = domain.wildcard? ? "wokku-check-#{SecureRandom.hex(4)}.#{domain.wildcard_parent}" : domain.hostname
    resolver = Resolv::DNS.new
    ips = []
    begin
      ips.concat(resolver.getresources(name, Resolv::DNS::Resource::IN::A).map { |r| r.address.to_s })
    rescue Resolv::ResolvError
    end
    begin
      ips.concat(resolver.getresources(name, Resolv::DNS::Resource::IN::AAAA).map { |r| r.address.to_s })
    rescue Resolv::ResolvError
    end

    ips.include?(server_ip)
  rescue StandardError => e
    Rails.logger.warn("DnsVerificationJob: resolve failed for #{domain.hostname}: #{e.message}")
    false
  end
end
