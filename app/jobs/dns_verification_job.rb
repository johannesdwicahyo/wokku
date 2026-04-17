class DnsVerificationJob < ApplicationJob
  queue_as :default

  def perform(domain_id)
    domain = Domain.find_by(id: domain_id)
    return unless domain

    if dns_verified?(domain.hostname)
      domain.update!(dns_verified: true)

      # Auto-enable SSL
      client = Dokku::Client.new(domain.app_record.server)
      Dokku::Domains.new(client).add(domain.app_record.name, domain.hostname)
      Dokku::Domains.new(client).enable_ssl(domain.app_record.name)
      domain.update!(ssl_enabled: true)
    end
  end

  private

  def dns_verified?(hostname)
    resolver = Resolv::DNS.new
    records = resolver.getresources(hostname, Resolv::DNS::Resource::IN::CNAME)
    records.any? { |r| r.name.to_s.downcase == "domains.wokku.cloud" }
  rescue Resolv::ResolvError
    false
  end
end
