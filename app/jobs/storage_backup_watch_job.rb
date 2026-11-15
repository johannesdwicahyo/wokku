# Hourly: email the founder when object-storage backups fail or go stale.
# Only servers that have ever reported are watched. One mail per kind per
# server per 12h (Rails.cache).
class StorageBackupWatchJob < ApplicationJob
  queue_as :health

  STALE_AFTER = 26.hours
  MAIL_EVERY = 12.hours

  def perform
    Server.where(id: StorageBackupRun.select(:server_id)).find_each do |server|
      runs = server.storage_backup_runs
      failed = runs.where(status: "failed").where("created_at > ?", 24.hours.ago).order(:created_at).last
      if failed && once?("failed", server)
        OpsMailer.storage_backup_failed(server, failed).deliver_later
      end

      last_ok = runs.sync_runs.where(status: "ok").maximum(:created_at)
      if (last_ok.nil? || last_ok < STALE_AFTER.ago) && once?("stale", server)
        OpsMailer.storage_backup_stale(server, last_ok).deliver_later
      end
    end
  end

  private

  def once?(kind, server)
    Rails.cache.write("storage_backup_watch:#{kind}:#{server.id}", true, unless_exist: true, expires_in: MAIL_EVERY)
  end
end
