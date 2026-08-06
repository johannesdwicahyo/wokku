class ApplyDynoTierJob < ApplicationJob
  queue_as :default

  def perform(dyno_allocation_id)
    allocation = DynoAllocation.find_by(id: dyno_allocation_id)
    return unless allocation

    app = allocation.app_record
    tier = allocation.dyno_tier

    success = false
    error_message = nil
    begin
      # Push resources + a restart in one declarative stack.converge
      # (converge sets resources from the web tier itself).
      Lifecycle::Ops.converge!(app, restart: true)
      success = true
    rescue Lifecycle::Ops::Failed, Lifecycle::Ops::Timeout, Lifecycle::Ops::Busy => e
      error_message = e.message.to_s.lines.first&.strip || e.class.name
      Rails.logger.warn "ApplyDynoTierJob failed for #{app.name}: #{error_message}"
    end

    # Clear the in-flight banner on the scaling page + surface a toast.
    # pending_action="resize" is set by scaling_controller#change_tier
    # before enqueueing.
    app.update(pending_action: nil) if app.pending_action == "resize"

    if success
      app.broadcast_action_toast(level: "success", message: "#{app.name} now on #{tier.name.upcase} tier.")
    else
      app.broadcast_action_toast(level: "error", message: "#{app.name} tier change failed — #{error_message}")
    end
  end
end
