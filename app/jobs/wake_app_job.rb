class WakeAppJob < ApplicationJob
  queue_as :default

  def perform(app_record_id)
    app = AppRecord.find_by(id: app_record_id)
    return unless app&.sleeping?

    # Converge back to the app's process_scales formation via wokkud.
    Lifecycle::Ops.converge!(app)
    app.running!
  rescue Lifecycle::Ops::Failed, Lifecycle::Ops::Timeout, Lifecycle::Ops::Busy => e
    Rails.logger.error("WakeAppJob: Failed to wake #{app&.name}: #{e.message}")
  end
end
