class PushNotificationService
  TITLES = {
    "deploy_succeeded" => "Deploy Succeeded",
    "deploy_failed" => "Deploy Failed",
    "app_crashed" => "App Crashed",
    "backup_completed" => "Backup Completed",
    "backup_failed" => "Backup Failed",
    "resource_high_cpu" => "High CPU Alert",
    "resource_high_memory" => "High Memory Alert",
    "app_down" => "App Down",
    "app_recovered" => "App Recovered"
  }.freeze

  CATEGORIES = {
    "deploy_succeeded" => "deploy",
    "deploy_failed" => "deploy",
    "app_crashed" => "alert",
    "backup_completed" => "backup",
    "backup_failed" => "alert",
    "resource_high_cpu" => "alert",
    "resource_high_memory" => "alert",
    "app_down" => "alert",
    "app_recovered" => "alert"
  }.freeze

  def initialize(notification, deploy, event, context = nil)
    @notification = notification
    @deploy = deploy
    @event = event
    @context = context || {}
    @client = Expo::Push::Client.new
  end

  def deliver!
    tokens = device_tokens
    return if tokens.empty?

    notifications = tokens.map { |dt| build_notification(dt) }
    tickets = @client.send(notifications)

    tokens_by_index = tokens.index_by.with_index { |dt, i| i }
    ticket_index = 0

    tickets.each do |ticket|
      dt = tokens[ticket_index]
      if dt
        PushTicket.create!(
          device_token: dt,
          ticket_id: ticket.id,
          status: "ok"
        )
      end
      ticket_index += 1
    end
  rescue StandardError => e
    Rails.logger.warn("Push notification failed: #{e.message}")
  end

  private

  def device_tokens
    user_ids = @notification.team.users.pluck(:id)
    DeviceToken.where(user_id: user_ids).to_a
  end

  def build_notification(device_token)
    # ponytail: deploy-less events (app_down/app_recovered) carry no
    # Deploy/AppRecord — only context. app_id is omitted from data so
    # deep-linking degrades to the notification list instead of crashing.
    app = @deploy&.app_record
    data = { type: "deploy", deploy_id: @deploy&.id, event: @event }
    data[:app_id] = app.id if app

    Expo::Push::Notification.new
      .to(device_token.token)
      .title(TITLES[@event] || @event.titleize)
      .body(build_body(app))
      .data(data)
      .sound("default")
      .category_id(CATEGORIES[@event] || "default")
  end

  def build_body(app)
    app_name = app&.name || @context["app_name"] || @context[:app_name] || "Wokku"
    commit = @deploy&.commit_sha&.first(7)
    version = @deploy&.release&.version

    case @event
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
    when "app_down"
      reason_message = @context["reason_message"] || @context[:reason_message]
      "#{app_name} is DOWN#{reason_message.present? ? ": #{reason_message}" : ""}"
    when "app_recovered"
      "#{app_name} is back up"
    else
      "#{app_name}: #{@event.humanize}"
    end
  end
end
