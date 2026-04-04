module Notifiable
  extend ActiveSupport::Concern

  private

  def fire_notifications(team, event, deploy)
    return unless team

    Notification.where(team: team).find_each do |notification|
      NotifyJob.perform_later(notification.id, event, deploy.id)
    end
  rescue StandardError => e
    Rails.logger.warn("Failed to fire notifications: #{e.message}")
  end

  def fire_resource_alert(team, event, app_record)
    return unless team
    Notification.where(team: team).find_each do |notification|
      next unless notification.events.include?(event)
      NotifyJob.perform_later(notification.id, event, app_record.deploys.last&.id || 0)
    end
  rescue StandardError => e
    Rails.logger.warn("Failed to fire resource alert: #{e.message}")
  end
end
