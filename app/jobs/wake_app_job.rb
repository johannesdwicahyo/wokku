class WakeAppJob < ApplicationJob
  queue_as :default

  def perform(app_record_id)
    app = AppRecord.find_by(id: app_record_id)
    # Only idle-slept free apps wake on a visit; a billing-suspended paid
    # app also sits at status: sleeping and must stay down.
    return unless app&.sleeping? && app.sleeping_tier?

    # Converge back to the app's process_scales formation via wokkud.
    Lifecycle::Ops.converge!(app)
    app.update!(status: :running, last_request_at: Time.current)
  rescue Lifecycle::Ops::Failed, Lifecycle::Ops::Timeout, Lifecycle::Ops::Busy, Lifecycle::Ops::RunNotAllowed, ArgumentError => e
    Rails.logger.error("WakeAppJob: Failed to wake #{app&.name}: #{e.class}: #{e.message}")
  end
end
