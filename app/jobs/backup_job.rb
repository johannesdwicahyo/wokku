class BackupJob < ApplicationJob
  queue_as :backups

  def perform(database_service_id)
    db = DatabaseService.find(database_service_id)
    BackupService.new(db).perform!
    Rails.logger.info("BackupJob: Backed up #{db.name} (#{db.service_type})")
  rescue => e
    Rails.logger.error("BackupJob: Failed to backup #{database_service_id}: #{e.message}")
  end
end
