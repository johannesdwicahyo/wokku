class NotifyJob < ApplicationJob
  queue_as :notifications

  # Optional `context` lets non-Deploy events (lifecycle, billing, etc.)
  # carry their own subject. Older callers pass nil and we fall back to
  # the Deploy's app for context.
  def perform(notification_id, event, deploy_id, context = nil)
    notification = Notification.find(notification_id)
    deploy = Deploy.find_by(id: deploy_id)

    return unless notification.events.include?(event)

    case notification.channel
    when "email"
      NotificationMailer.deploy_notification(notification, deploy, event, context).deliver_later
    when "slack"
      send_slack(notification, deploy, event, context)
    when "webhook"
      send_webhook(notification, deploy, event, context)
    when "discord"
      send_discord(notification, deploy, event, context)
    when "telegram"
      send_telegram(notification, deploy, event, context)
    when "push"
      PushNotificationService.new(notification, deploy, event).deliver!
    end
  end

  private

  def build_message(deploy, event, context = nil)
    # Test deliveries: deploy=nil AND no event-specific context.
    if deploy.nil? && context.blank?
      return "Wokku test notification — channel is working ✅"
    end

    app_name = deploy&.app_record&.name || context&.dig("app_name") || context&.dig(:app_name) || "Wokku"
    commit = deploy&.commit_sha&.first(7)
    version = deploy&.release&.version

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
    when "app_created"
      "#{app_name} created"
    when "app_deleted"
      "#{app_name} deleted"
    when "daily_debit_summary"
      amount = context&.dig("amount") || context&.dig(:amount)
      currency = context&.dig("currency") || context&.dig(:currency) || "idr"
      formatted = currency == "idr" ? "Rp #{ActiveSupport::NumberHelper.number_to_delimited(amount.to_i, delimiter: '.')}" : "$#{'%.2f' % (amount.to_i / 100.0)}"
      "Wokku daily usage: #{formatted} debited for yesterday"
    else
      "#{app_name}: #{event}"
    end
  end

  def send_slack(notification, deploy, event, context = nil)
    url = notification.config["url"]
    return unless url.present?

    payload = {
      text: build_message(deploy, event, context),
      username: "Wokku",
      icon_emoji: ":rocket:"
    }
    post_json(url, payload)
  rescue StandardError => e
    Rails.logger.warn("Slack notification failed: #{e.message}")
  end

  def send_discord(notification, deploy, event, context = nil)
    url = notification.config["url"]
    return unless url.present?

    payload = {
      content: build_message(deploy, event, context),
      username: "Wokku"
    }
    post_json(url, payload)
  rescue StandardError => e
    Rails.logger.warn("Discord notification failed: #{e.message}")
  end

  def send_telegram(notification, deploy, event, context = nil)
    bot_token = notification.config["bot_token"]
    chat_id = notification.config["chat_id"]
    return unless bot_token.present? && chat_id.present?

    url = "https://api.telegram.org/bot#{bot_token}/sendMessage"
    payload = {
      chat_id: chat_id,
      text: build_message(deploy, event, context),
      parse_mode: "HTML"
    }
    post_json(url, payload)
  rescue StandardError => e
    Rails.logger.warn("Telegram notification failed: #{e.message}")
  end

  def send_webhook(notification, deploy, event, context = nil)
    url = notification.config["url"]
    return unless url.present?

    payload = {
      event: event,
      app: deploy&.app_record&.name || context&.dig("app_name") || context&.dig(:app_name),
      deploy_id: deploy&.id,
      status: deploy&.status,
      commit_sha: deploy&.commit_sha,
      message: build_message(deploy, event, context),
      context: context,
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
