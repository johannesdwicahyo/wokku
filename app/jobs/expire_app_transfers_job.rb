class ExpireAppTransfersJob < ApplicationJob
  include SentryMonitored
  monitor_with_sentry "expire-app-transfers"

  queue_as :default

  def perform
    AppTransfer.where(status: "pending").where("expires_at <= ?", Time.current)
               .find_each { |t| t.update!(status: "expired") }
  end
end
