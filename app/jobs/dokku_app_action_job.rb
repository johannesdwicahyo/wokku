class DokkuAppActionJob < ApplicationJob
  queue_as :default

  ALLOWED_ACTIONS = %w[restart stop start].freeze

  # Async wrapper for restart / stop / start. The dashboard used to call
  # these synchronously, which routinely gateway-timed-out at kamal-proxy's
  # 30s response cap. Async + Solid Queue keeps state consistent and lets
  # the controller respond immediately so the user sees feedback.
  def perform(app_id, action)
    raise ArgumentError, "Unknown action #{action.inspect}" unless ALLOWED_ACTIONS.include?(action.to_s)

    app = AppRecord.find_by(id: app_id)
    return unless app

    # Suspension may land between enqueue and pickup (or a caller skipped
    # the controller gate): never bring a suspended account's app up.
    if action.to_s != "stop" && !app.run_allowed?
      app.update(pending_action: nil)
      app.broadcast_action_toast(level: "error", message: "#{app.name}: #{AppRecord::RUN_BLOCKED_MESSAGE}")
      return
    end

    success = false
    error_message = nil
    begin
      converge_action!(app, action.to_s)
      success = true
    rescue Lifecycle::Ops::Failed, Lifecycle::Ops::Timeout => e
      error_message = e.message.to_s.lines.first&.strip || e.class.name
      Rails.logger.warn("DokkuAppActionJob #{action} failed for #{app.name}: #{error_message}")
    rescue StandardError => e
      # Safety net: any unexpected error (Timeout::Error, Net::SSH::*,
      # IOError, etc.) must still fall through so pending_action gets
      # cleared below. Without this the UI stays stuck on "Restarting…"
      # even though the container restarted fine.
      error_message = e.message.to_s.lines.first&.strip || e.class.name
      Rails.logger.error("DokkuAppActionJob #{action} unexpected error for #{app.name}: #{e.class}: #{error_message}")
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
    # A user-started app gets a fresh idle window; otherwise an idle-slept
    # app is re-slept by the next IdleCheckJob sweep.
    update_attrs[:last_request_at] = Time.current if new_status == :running
    app.update(update_attrs)

    if success
      Activity.log(user: app.creator, team: app.team, action: "app.#{action}ed", target: app) rescue nil
      app.broadcast_action_toast(level: "success", message: "#{app.name}: #{action} complete.")
    else
      app.broadcast_action_toast(level: "error", message: "#{app.name}: #{action} failed — #{error_message}")
    end
  end

  private

  # Apps reconcile declaratively via stack.converge. Stop zeroes every
  # process; start/restart converge the app's process_scales formation
  # back up.
  def converge_action!(app, action)
    case action
    when "restart"
      Lifecycle::Ops.converge!(app, restart: true)
    when "stop"
      Lifecycle::Ops.converge!(app, formation: Lifecycle::Ops.stop_formation(app), allow_empty: true)
    when "start"
      Lifecycle::Ops.converge!(app)
    end
  end
end
