class DnsVerificationSchedulerJob < ApplicationJob
  def perform
    Domain.where(dns_verified: false).find_each do |domain|
      DnsVerificationJob.perform_later(domain.id)
    end
  end
end
