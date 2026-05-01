class BackupJob < ApplicationJob
  queue_as :backups

  def perform(database_service_id)
    db = DatabaseService.find(database_service_id)
    BackupService.new(db).perform!
    Rails.logger.info("BackupJob: Backed up #{db.name} (#{db.service_type})")
  rescue => e
    Rails.logger.error("BackupJob: Failed to backup #{database_service_id}: #{e.message}")
    Sentry.capture_exception(e, extra: { database_service_id: database_service_id }) if defined?(Sentry)

    # Notify the team owner so backup failures are never silent
    db = DatabaseService.find_by(id: database_service_id)
    if db && db.server&.team
      fire_notifications(db.server.team, "backup_failed", db) rescue nil
    end
  end
end
