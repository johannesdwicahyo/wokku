class BackupRetentionJob < ApplicationJob
  queue_as :backups

  def perform
    BackupDestination.where(enabled: true).find_each do |dest|
      expired = Backup.where(backup_destination: dest, status: "completed")
        .where("created_at < ?", dest.retention_days.days.ago)

      expired.find_each do |backup|
        begin
          dest.s3_client.delete_object(bucket: dest.bucket, key: backup.s3_key)
          backup.destroy!
          Rails.logger.info("BackupRetentionJob: Deleted expired backup #{backup.s3_key}")
        rescue => e
          Rails.logger.error("BackupRetentionJob: Failed to delete #{backup.s3_key}: #{e.message}")
        end
      end
    end
  end
end
