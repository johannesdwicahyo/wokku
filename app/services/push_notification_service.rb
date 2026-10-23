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
    tokens = recipient_tokens
    return if tokens.empty?

    begin
      deliver_expo(tokens.select { |dt| dt.provider == "expo" })
    rescue StandardError => e
      Rails.logger.warn("Expo push failed: #{e.class}") # never e.message: may carry a token
    end

    apns = tokens.select { |dt| dt.provider == "apns" }
    return if apns.empty?

    begin
      Push::Apns.new.deliver(apns, title: TITLES[@event] || @event.titleize, body: build_body(subject_app),
                                   category: CATEGORIES[@event] || "default", data: push_data)
    rescue StandardError => e
      Rails.logger.warn("APNs push failed: #{e.class}")
    end
  rescue StandardError => e
    Rails.logger.warn("Push notification failed: #{e.class}")
  end

  # Custom keys the app uses to open the right screen.
  def push_data
    { type: "deploy", event: @event, app_id: subject_app&.id,
      deploy_id: @deploy&.id, incident_id: context_value("incident_id") }.compact
  end

  private

  def deliver_expo(tokens)
    tokens = tokens.select { |dt| Expo::Push.expo_push_token?(dt.token) }
    return if tokens.empty?

    notifications = tokens.map { |dt| build_notification(dt) }
    tickets = @client.send(notifications)

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
  end

  # Team members with a device, minus anyone who muted this app/event.
  # ponytail: one mute query per member; teams are small. Batch it if a
  # team ever has hundreds of phones.
  def recipient_tokens
    app = subject_app
    users = @notification.team.users.reject { |u| AlertMute.muted?(user: u, app_record: app, event: @event) }
    DeviceToken.where(user_id: users.map(&:id)).to_a
  end

  def subject_app
    return @subject_app if defined?(@subject_app)
    @subject_app = @deploy&.app_record || ((id = context_value("app_id")) && AppRecord.find_by(id: id))
  end

  def context_value(key) = @context[key] || @context[key.to_sym]

  def build_notification(device_token)
    app = subject_app

    Expo::Push::Notification.new
      .to(device_token.token)
      .title(TITLES[@event] || @event.titleize)
      .body(build_body(app))
      .data(push_data)
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
