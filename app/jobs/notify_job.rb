require "ssrf_filter"

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
      PushNotificationService.new(notification, deploy, event, context).deliver!
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
    when "deploy_started"
      "#{app_name} deploy started#{commit ? " (#{commit})" : ""}"
    when "deploy_succeeded"
      "#{app_name} deployed successfully#{commit ? " (#{commit})" : ""}#{version ? " v#{version}" : ""}"
    when "deploy_failed"
      "#{app_name} deploy failed#{commit ? " (#{commit})" : ""}"
    when "app_crashed"
      "#{app_name} has crashed"
    when "app_auto_stopped"
      "#{app_name} was auto-stopped after crash-looping — deploy a fix to restart it"
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
      formatted = currency == "idr" ? "Rp#{ActiveSupport::NumberHelper.number_to_delimited(amount.to_i, delimiter: '.')}" : "$#{'%.2f' % (amount.to_i / 100.0)}"
      "Wokku daily usage: #{formatted} debited for yesterday"
    when "app_down"
      reason = context&.dig("reason") || context&.dig(:reason)
      if reason == "app_stopped"
        "#{app_name} was stopped"
      else
        reason_message = context&.dig("reason_message") || context&.dig(:reason_message)
        "#{app_name} is DOWN#{reason_message.present? ? ": #{reason_message}" : ""}"
      end
    when "app_recovered"
      "#{app_name} is back up"
    when "scheduled_task_failing"
      task_command = context&.dig("task_command") || context&.dig(:task_command)
      exit_code = context&.dig("exit_code") || context&.dig(:exit_code)
      "#{app_name}: scheduled task `#{task_command}` has failed 3 times in a row (last exit #{exit_code})"
    when "scheduled_task_recovered"
      task_command = context&.dig("task_command") || context&.dig(:task_command)
      "#{app_name}: scheduled task `#{task_command}` is passing again"
    else
      "#{app_name}: #{event}"
    end
  end

  # Slack messages use the legacy `attachments` API for the color sidebar
  # — modern Block Kit is richer but requires the bot OAuth flow; we use
  # incoming webhooks which still respect attachments and field rows.
  def send_slack(notification, deploy, event, context = nil)
    url = notification.config["url"]
    return unless url.present?

    color = slack_color_for(event)
    message = build_message(deploy, event, context)
    fields = deploy_fields(deploy)
    dashboard_url = dashboard_link_for(deploy)

    if color || fields.any? || dashboard_url
      payload = {
        username: "Wokku",
        icon_emoji: ":rocket:",
        attachments: [ {
          color: color,
          fallback: message,
          title: message,
          title_link: dashboard_url,
          fields: fields,
          footer: "Wokku Cloud",
          ts: Time.current.to_i
        }.compact ]
      }
    else
      payload = { text: message, username: "Wokku", icon_emoji: ":rocket:" }
    end
    post_json(url, payload)
  rescue StandardError => e
    Rails.logger.warn("Slack notification failed: #{e.message}")
  end

  # Discord webhooks accept an `embeds` array. Color is a base-10 int.
  def send_discord(notification, deploy, event, context = nil)
    url = notification.config["url"]
    return unless url.present?

    message = build_message(deploy, event, context)
    color_hex = discord_color_for(event)
    fields = deploy_fields(deploy).map { |f| { name: f[:title], value: f[:value].to_s, inline: true } }
    dashboard_url = dashboard_link_for(deploy)

    payload = {
      username: "Wokku",
      embeds: [ {
        title: message,
        url: dashboard_url,
        color: color_hex,
        fields: fields,
        timestamp: Time.current.iso8601
      }.compact ]
    }
    post_json(url, payload)
  rescue StandardError => e
    Rails.logger.warn("Discord notification failed: #{e.message}")
  end

  def slack_color_for(event)
    case event
    when "deploy_succeeded", "app_created", "app_recovered", "scheduled_task_recovered"        then "good"     # green
    when "deploy_failed", "app_crashed", "backup_failed", "resource_high_cpu", "resource_high_memory", "app_down", "scheduled_task_failing" then "danger"   # red
    when "deploy_started"                          then "#3b82f6"  # blue
    when "app_deleted", "daily_debit_summary"      then "warning"  # yellow
    end
  end

  def discord_color_for(event)
    case event
    when "deploy_succeeded", "app_created", "app_recovered", "scheduled_task_recovered"        then 0x22c55e # green
    when "deploy_failed", "app_crashed", "backup_failed", "resource_high_cpu", "resource_high_memory", "app_down", "scheduled_task_failing" then 0xef4444 # red
    when "deploy_started"                          then 0x3b82f6 # blue
    when "app_deleted", "daily_debit_summary"      then 0xeab308 # yellow
    end
  end

  def deploy_fields(deploy)
    return [] unless deploy
    out = []
    if deploy.commit_sha.present?
      out << { title: "Commit", value: deploy.commit_sha.first(7), short: true }
    end
    if deploy.release&.version
      out << { title: "Release", value: "v#{deploy.release.version}", short: true }
    end
    if deploy.duration
      out << { title: "Duration", value: "#{deploy.duration.round}s", short: true }
    end
    out
  end

  def dashboard_link_for(deploy)
    return nil unless deploy&.app_record
    base = ENV["APP_URL"].presence || "https://wokku.cloud"
    "#{base}/dashboard/apps/#{deploy.app_record.id}/releases"
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

  # SSRF guard: notification destination URLs (slack/discord/generic
  # webhook) are set by team admins and delivered server-side, incl. an
  # on-demand  action. SsrfFilter resolves + validates a public IP,
  # pins the socket (anti-rebinding), and revalidates redirects, so a
  # crafted URL can't make the control plane POST to internal services.
  def post_json(url, payload)
    SsrfFilter.post(url,
      headers: { "Content-Type" => "application/json" },
      body: payload.to_json,
      http_options: { open_timeout: 5, read_timeout: 10 })
  rescue SsrfFilter::Error => e
    Rails.logger.warn("notification webhook blocked by SSRF guard: #{e.class}")
    nil
  end
end
