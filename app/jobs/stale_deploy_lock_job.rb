# Detects an app whose deploy lock has been held beyond STALE_AFTER and
# alerts the operator + releases it (deploy_locked_at on the app row —
# see Apps::Lifecycle::DeployLock).
class StaleDeployLockJob < ApplicationJob
  queue_as :health

  STALE_AFTER = 15 * 60

  def perform(server_id)
    server = Server.find_by(id: server_id)
    return unless server

    server.app_records.find_each do |app|
      lock = Apps::Lifecycle::DeployLock.new(app)
      unless locked_safely?(lock)
        Rails.cache.delete(seen_key(app))
        next
      end

      first = Rails.cache.fetch(seen_key(app), expires_in: 2.hours) { Time.now.to_i }
      next unless (Time.now.to_i - first) >= STALE_AFTER

      Rails.logger.warn("StaleDeployLockJob: #{app.name} locked > #{STALE_AFTER}s; alerting + releasing")
      if defined?(Sentry)
        Sentry.capture_message("stale deploy lock: #{app.name}", level: :warning,
                               extra: { app_id: app.id, server: server.name })
      end
      begin
        lock.unlock!
      rescue StandardError => e
        Rails.logger.warn("StaleDeployLockJob: unlock! failed for #{app.name}: #{e.message}")
      end
      Rails.cache.delete(seen_key(app))
    end
  rescue StandardError => e
    Sentry.capture_exception(e, level: :warning, extra: { server_id: server_id }) if defined?(Sentry)
  end

  private

  def locked_safely?(lock)
    lock.locked?
  rescue StandardError
    false
  end

  def seen_key(app) = "stalelock:seen:#{app.id}"
end
