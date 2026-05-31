class DnsVerificationSchedulerJob < ApplicationJob
  def perform
    pending = SolidQueue::Job.where(class_name: "DnsVerificationJob", finished_at: nil).count
    cap = 200
    if pending >= cap
      Rails.logger.warn("DnsVerificationSchedulerJob: #{pending} pending >= cap #{cap}; skipping tick")
      return
    end

    Domain.where(dns_verified: false).find_each do |domain|
      DnsVerificationJob.perform_later(domain.id)
    end
  end
end
