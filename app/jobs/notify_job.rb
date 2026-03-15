class NotifyJob < ApplicationJob
  queue_as :notifications

  def perform(notification_id, event, deploy_id)
    notification = Notification.find(notification_id)
    deploy = Deploy.find(deploy_id)

    return unless notification.events.include?(event)

    case notification.channel
    when "email"
      NotificationMailer.deploy_notification(notification, deploy, event).deliver_later
    when "slack"
      send_slack(notification, deploy, event) if Wokku.ee?
    when "webhook"
      send_webhook(notification, deploy, event) if Wokku.ee?
    end
  end

  private

  def send_slack(notification, deploy, event)
    url = notification.config["url"]
    payload = {
      text: "[#{deploy.app_record.name}] Deploy #{event}: #{deploy.commit_sha&.first(7)} (v#{deploy.release&.version})"
    }
    post_with_timeout(url, payload)
  rescue StandardError => e
    Rails.logger.warn("Slack notification failed: #{e.message}")
  end

  def send_webhook(notification, deploy, event)
    url = notification.config["url"]
    payload = {
      event: event,
      app: deploy.app_record.name,
      deploy_id: deploy.id,
      status: deploy.status,
      commit_sha: deploy.commit_sha
    }
    post_with_timeout(url, payload)
  rescue StandardError => e
    Rails.logger.warn("Webhook notification failed: #{e.message}")
  end

  def post_with_timeout(url, payload)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10
    request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
    request.body = payload.to_json
    http.request(request)
  end
end
