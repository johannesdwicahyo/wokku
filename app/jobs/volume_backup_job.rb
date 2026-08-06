# Nightly per-app volume backup: every declared storage mount (anchored under
# the dokku storage root) is tarred, encrypted, and shipped to R2. Per-mount
# failures are isolated so one bad mount doesn't skip the rest.
class VolumeBackupJob < ApplicationJob
  queue_as :backups

  def perform(app_record_id)
    app = AppRecord.find_by(id: app_record_id)
    return unless app

    VolumeBackupService.mount_host_paths(app).each do |mount|
      VolumeBackupService.new(app, mount).perform!
    rescue => e
      if vanished_mount?(e)
        # A removed mount on a stopped/rebuilt app is expected churn, not an
        # incident — warn only, skip Sentry.
        Rails.logger.warn("[VolumeBackupJob] #{app.name} #{mount}: mount vanished, skipping: #{e.message}")
      else
        Rails.logger.error("[VolumeBackupJob] #{app.name} #{mount}: #{e.class}: #{e.message}")
        Sentry.capture_exception(e, extra: { app: app.name, mount: mount }) if defined?(Sentry)
      end
    end
  end

  private

  def vanished_mount?(e)
    e.is_a?(Hosts::Ssh::CommandError) && e.stderr.to_s.match?(/No such file or directory/i)
  end
end
