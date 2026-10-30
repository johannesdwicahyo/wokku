# Restores run here, not in the request: the service.import op waits up to
# 300 s and kamal-proxy cuts responses at ~30 s, so a real-size restore
# showed a gateway error while still running (inviting a second restore).
# The outcome lands in the team's activity feed.
class RestoreJob < ApplicationJob
  queue_as :backups

  def perform(backup_id, user_id)
    backup = Backup.find(backup_id)
    db = backup.database_service
    RestoreService.new(backup).perform!
    log(db, user_id, "database.restored", backup_id: backup.id)
  rescue ActiveRecord::RecordNotFound
    nil # backup or database deleted meanwhile
  rescue => e
    Rails.logger.error("RestoreJob: #{backup_id}: #{e.class}: #{e.message}")
    Sentry.capture_exception(e, extra: { backup_id: backup_id }) if defined?(Sentry)
    # Never the exception text in the feed: op output can carry hosts and
    # credentials. Details go to Sentry above.
    log(db, user_id, "database.restore_failed", backup_id: backup_id, error: "The restore did not complete. Retry, or contact support.") if db
  end

  private

  def log(db, user_id, action, metadata)
    team = db.app_records.first&.team || User.find_by(id: user_id)&.teams&.first
    return unless team
    Activity.log(user: User.find_by(id: user_id), team: team, action: action, target: db,
                 metadata: metadata.merge(service_type: db.service_type))
  end
end
