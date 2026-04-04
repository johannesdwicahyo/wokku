class NotifyJob < ApplicationJob
  queue_as :notifications

  def perform(notification_id, event, deploy_id)
    notification = Notification.find(notification_id)
    deploy = Deploy.find_by(id: deploy_id)

    return unless notification.events.include?(event)

    case notification.channel
    when "email"
      NotificationMailer.deploy_notification(notification, deploy, event).deliver_later
    when "slack"
      send_slack(notification, deploy, event)
    when "webhook"
      send_webhook(notification, deploy, event)
    when "discord"
      send_discord(notification, deploy, event)
    when "telegram"
      send_telegram(notification, deploy, event)
    when "push"
      PushNotificationService.new(notification, deploy, event).deliver!
    end
  end

  private

  def build_message(deploy, event)
    return event.humanize if deploy.nil?

    app_name = deploy.app_record.name
    commit = deploy.commit_sha&.first(7)
    version = deploy.release&.version

    case event
    when "deploy_succeeded"
      "#{app_name} deployed successfully#{commit ? " (#{commit})" : ""}#{version ? " v#{version}" : ""}"
    when "deploy_failed"
      "#{app_name} deploy failed#{commit ? " (#{commit})" : ""}"
    when "app_crashed"
      "#{app_name} has crashed"
    when "backup_completed"
      "#{app_name} backup completed"
    when "backup_failed"
      "#{app_name} backup failed"
    when "resource_high_cpu"
      "#{app_name} CPU usage is above 80%"
    when "resource_high_memory"
      "#{app_name} memory usage is above 90%"
    else
      "#{app_name}: #{event}"
    end
  end

  def send_slack(notification, deploy, event)
    url = notification.config["url"]
    return unless url.present?

    payload = {
      text: build_message(deploy, event),
      username: "Wokku",
      icon_emoji: ":rocket:"
    }
    post_json(url, payload)
  rescue StandardError => e
    Rails.logger.warn("Slack notification failed: #{e.message}")
  end

  def send_discord(notification, deploy, event)
    url = notification.config["url"]
    return unless url.present?

    # Discord webhooks accept Slack-compatible format with "content" key
    payload = {
      content: build_message(deploy, event),
      username: "Wokku"
    }
    post_json(url, payload)
  rescue StandardError => e
    Rails.logger.warn("Discord notification failed: #{e.message}")
  end

  def send_telegram(notification, deploy, event)
    bot_token = notification.config["bot_token"]
    chat_id = notification.config["chat_id"]
    return unless bot_token.present? && chat_id.present?

    url = "https://api.telegram.org/bot#{bot_token}/sendMessage"
    payload = {
      chat_id: chat_id,
      text: build_message(deploy, event),
      parse_mode: "HTML"
    }
    post_json(url, payload)
  rescue StandardError => e
    Rails.logger.warn("Telegram notification failed: #{e.message}")
  end

  def send_webhook(notification, deploy, event)
    url = notification.config["url"]
    return unless url.present?

    payload = {
      event: event,
      app: deploy&.app_record&.name,
      deploy_id: deploy&.id,
      status: deploy&.status,
      commit_sha: deploy&.commit_sha,
      message: build_message(deploy, event),
      timestamp: Time.current.iso8601
    }
    post_json(url, payload)
  rescue StandardError => e
    Rails.logger.warn("Webhook notification failed: #{e.message}")
  end

  def post_json(url, payload)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    request.body = payload.to_json
    http.request(request)
  end
end
