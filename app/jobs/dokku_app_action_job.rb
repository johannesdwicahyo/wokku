class DokkuAppActionJob < ApplicationJob
  queue_as :default

  ALLOWED_ACTIONS = %w[restart stop start].freeze

  # Async wrapper for `dokku ps:restart` / `:stop` / `:start`. The dashboard
  # used to call these synchronously, which routinely gateway-timed-out at
  # kamal-proxy's 30s response cap because Dokku's zero-downtime deploy
  # waits on HTTP checks before completing. With Timeout.timeout enforced
  # in Dokku::Client, the SSH session was being killed mid-flight, leaving
  # the host with both old + new containers running (caught on
  # wicara-rails 2026-04-30). Async + Solid Queue keeps state consistent
  # and lets the controller respond immediately so the user sees feedback.
  def perform(app_id, action)
    raise ArgumentError, "Unknown action #{action.inspect}" unless ALLOWED_ACTIONS.include?(action.to_s)

    app = AppRecord.find_by(id: app_id)
    return unless app

    success = false
    error_message = nil
    begin
      client = Dokku::Client.new(app.server)
      Dokku::Processes.new(client).public_send(action.to_sym, app.name)
      success = true
    rescue Dokku::Client::CommandError, Dokku::Client::ConnectionError => e
      error_message = e.message.to_s.lines.first&.strip || e.class.name
      Rails.logger.warn("DokkuAppActionJob #{action} failed for #{app.name}: #{error_message}")
    end

    new_status =
      if !success && action.to_s == "start"
        :crashed
      elsif success
        case action.to_s
        when "stop"             then :stopped
        when "start", "restart" then :running
        end
      end

    # Always clear pending_action so the dashboard's sticky button state
    # resets even on failure. after_update_commit broadcasts the new
    # state + a toast to subscribed pages.
    update_attrs = { pending_action: nil }
    update_attrs[:status] = new_status if new_status
    app.update(update_attrs)

    if success
      Activity.log(user: app.creator, team: app.team, action: "app.#{action}ed", target: app) rescue nil
      app.broadcast_action_toast(level: "success", message: "#{app.name}: #{action} complete.")
    else
      app.broadcast_action_toast(level: "error", message: "#{app.name}: #{action} failed — #{error_message}")
    end
  end
end
