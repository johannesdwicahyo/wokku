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
      NotifyJob.perform_later(notification.id, event, app_record.deploys.last&.id || 0,
                              { "app_id" => app_record.id, "app_name" => app_record.name })
    end
  rescue StandardError => e
    Rails.logger.warn("Failed to fire resource alert: #{e.message}")
  end

  # Generic dispatcher for events that don't carry a Deploy. The
  # context hash is forwarded to NotifyJob and surfaces in the
  # message body / mail subject (e.g. lifecycle events with just an
  # app name, or billing events with an amount).
  def fire_team_event(team, event, context = {})
    return unless team
    Notification.where(team: team).find_each do |notification|
      next unless notification.events.include?(event)
      NotifyJob.perform_later(notification.id, event, 0, context.deep_stringify_keys)
    end
  rescue StandardError => e
    Rails.logger.warn("Failed to fire team event: #{e.message}")
  end
end
