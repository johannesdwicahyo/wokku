class BackupRetentionJob < ApplicationJob
  queue_as :backups

  def perform
    DatabaseService.where(status: :running).find_each do |db|
      retention = db.backup_policy[:retention_days]

      db.backups.where(status: "completed")
        .where("created_at < ?", retention.days.ago)
        .find_each do |backup|
          delete_backup(backup)
        end
    end
  end

  private

  def delete_backup(backup)
    dest = backup.backup_destination
    dest.s3_client.delete_object(bucket: dest.bucket, key: backup.s3_key)
    backup.destroy!
    Rails.logger.info("BackupRetentionJob: Deleted backup #{backup.s3_key}")
  rescue => e
    Rails.logger.error("BackupRetentionJob: Failed to delete #{backup.s3_key}: #{e.message}")
  end
end
