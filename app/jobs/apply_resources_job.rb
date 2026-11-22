class ApplyResourcesJob < ApplicationJob
  queue_as :default

  # Push per-process resources in one declarative stack.converge (converge
  # reads each process's allocation — Lifecycle::Ops.resources_for). No forced
  # restart: resources are part of each service's spec hash, so wokkud rolls
  # only the resized process (all 99 live services carry the hash, 2026-11-22).
  def perform(app_id)
    app = AppRecord.find_by(id: app_id)
    return unless app

    error = nil
    begin
      Lifecycle::Ops.converge!(app)
    rescue StandardError => e
      error = e.message.to_s.lines.first&.strip.presence || e.class.name
      Rails.logger.warn "ApplyResourcesJob failed for #{app.name}: #{e.class}: #{error}"
    ensure
      app.update(pending_action: nil) if app.pending_action == "resize"
    end

    if error
      app.broadcast_action_toast(level: "error", message: "#{app.name} resize failed — #{error}")
    else
      app.broadcast_action_toast(level: "success", message: "#{app.name} resized.")
    end
  end
end
