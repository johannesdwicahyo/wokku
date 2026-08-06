class DnsVerificationSchedulerJob < ApplicationJob
  def perform
    return if scheduler_saturated?("DnsVerificationJob", cap: 200)

    Domain.where(dns_verified: false).find_each do |domain|
      DnsVerificationJob.perform_later(domain.id)
    end
  end
end
