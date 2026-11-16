# Daily on self-host: is a newer release published? Records it for the
# admin banner and emails the admin once per release. wokku.cloud deploys
# itself, so it never runs there. Opt out with WOKKU_UPDATE_CHECK=0.
class UpdateCheckJob < ApplicationJob
  queue_as :default

  def perform
    return if Wokku.cloud? || ENV["WOKKU_UPDATE_CHECK"] == "0"
    current = ENV["WOKKU_VERSION"].to_s
    return unless current.match?(Wokku::UpdateChecker::VERSION_FORMAT) # dev/local builds

    latest = Wokku::UpdateChecker.latest_version or return
    status = UpdateStatus.current
    status.update!(latest_version: latest, checked_at: Time.current)
    return unless status.update_available?(current) && status.notified_version != latest

    admin = User.find_by(role: :admin) or return
    UpdateMailer.available(admin, current: current, latest: latest).deliver_later
    status.update!(notified_version: latest)
  end
end
