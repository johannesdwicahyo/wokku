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
end
