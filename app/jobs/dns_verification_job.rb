class DnsVerificationJob < ApplicationJob
  queue_as :default

  def perform(domain_id)
    domain = Domain.find_by(id: domain_id)
    return unless domain
    return unless dns_verified?(domain)

    domain.update!(dns_verified: true)

    # Auto-enable SSL on the first successful verification. Idempotent —
    # re-enabling for an app that already has letsencrypt turned on is a
    # cheap no-op on the Dokku side.
    client = Dokku::Client.new(domain.app_record.server)
    Dokku::Domains.new(client).add(domain.app_record.name, domain.hostname)
    Dokku::Domains.new(client).enable_ssl(domain.app_record.name)
    domain.update!(ssl_enabled: true)
  rescue Dokku::Client::ConnectionError, Dokku::Client::CommandError => e
    Rails.logger.warn("DnsVerificationJob: SSL enable failed for #{domain&.hostname}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end

  private

  # A domain is considered verified if the DNS it resolves to matches
  # what wokku.cloud serves. Two shapes are valid:
  #
  #   1. Subdomain with a CNAME to the app's wokku.cloud hostname
  #      (what `PostDeploySetupJob` creates via Cloudflare), e.g.
  #      `app.example.com` CNAME → `my-app.wokku.cloud`.
  #   2. Apex or any host with A/AAAA records that resolve to the
  #      Dokku server's public IP. DNS spec forbids CNAME on apex, so
  #      this is the only path for root domains like `wokku.dev`.
  #
  # We don't require the CNAME target literally — we follow it to the
  # A record and compare IPs, so ALIAS/ANAME/flattening all work too.
  def dns_verified?(domain)
    server_ip = domain.app_record.server&.host.to_s
    return false if server_ip.blank?

    resolver = Resolv::DNS.new
    ips = []
    begin
      ips.concat(resolver.getresources(domain.hostname, Resolv::DNS::Resource::IN::A).map { |r| r.address.to_s })
    rescue Resolv::ResolvError
    end
    begin
      ips.concat(resolver.getresources(domain.hostname, Resolv::DNS::Resource::IN::AAAA).map { |r| r.address.to_s })
    rescue Resolv::ResolvError
    end

    ips.include?(server_ip)
  rescue StandardError => e
    Rails.logger.warn("DnsVerificationJob: resolve failed for #{domain.hostname}: #{e.message}")
    false
  end
end
