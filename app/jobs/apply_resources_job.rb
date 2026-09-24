class ApplyResourcesJob < ApplicationJob
  queue_as :default

  # Push per-process resources + a restart in one declarative stack.converge
  # (converge reads each process's allocation — Lifecycle::Ops.resources_for).
  def perform(app_id)
    app = AppRecord.find_by(id: app_id)
    return unless app

    error = nil
    begin
      Lifecycle::Ops.converge!(app, restart: true)
    rescue Lifecycle::Ops::Failed, Lifecycle::Ops::Timeout, Lifecycle::Ops::Busy => e
      error = e.message.to_s.lines.first&.strip || e.class.name
      Rails.logger.warn "ApplyResourcesJob failed for #{app.name}: #{error}"
    end

    app.update(pending_action: nil) if app.pending_action == "resize"
    if error
      app.broadcast_action_toast(level: "error", message: "#{app.name} resize failed — #{error}")
    else
      app.broadcast_action_toast(level: "success", message: "#{app.name} resized.")
    end
  end
end
