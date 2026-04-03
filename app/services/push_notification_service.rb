class PushNotificationService
  TITLES = {
    "deploy_succeeded" => "Deploy Succeeded",
    "deploy_failed" => "Deploy Failed",
    "app_crashed" => "App Crashed",
    "backup_completed" => "Backup Completed",
    "backup_failed" => "Backup Failed"
  }.freeze

  CATEGORIES = {
    "deploy_succeeded" => "deploy",
    "deploy_failed" => "deploy",
    "app_crashed" => "alert",
    "backup_completed" => "backup",
    "backup_failed" => "alert"
  }.freeze

  def initialize(notification, deploy, event)
    @notification = notification
    @deploy = deploy
    @event = event
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
    app = @deploy.app_record
    Expo::Push::Notification.new
      .to(device_token.token)
      .title(TITLES[@event] || @event.titleize)
      .body(build_body(app))
      .data({
        type: "deploy",
        app_id: app.id,
        deploy_id: @deploy.id,
        event: @event
      })
      .sound("default")
      .category_id(CATEGORIES[@event] || "default")
  end

  def build_body(app)
    commit = @deploy.commit_sha&.first(7)
    version = @deploy.release&.version

    case @event
    when "deploy_succeeded"
      "#{app.name} deployed successfully#{commit ? " (#{commit})" : ""}#{version ? " v#{version}" : ""}"
    when "deploy_failed"
      "#{app.name} deploy failed#{commit ? " (#{commit})" : ""}"
    when "app_crashed"
      "#{app.name} has crashed"
    when "backup_completed"
      "#{app.name} backup completed"
    when "backup_failed"
      "#{app.name} backup failed"
    else
      "#{app.name}: #{@event.humanize}"
    end
  end
end
