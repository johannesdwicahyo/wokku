module ImageScans
  # Queue a scan of the deploy's image. Never raises into the caller (a deploy).
  class Enqueue
    def self.call(app:, deploy:, trigger:)
      return nil unless Wokku.config.image_scans?
      ref = deploy&.image_ref
      return nil if ref.blank? || app.server_id.blank?

      ImageScan.transaction do
        ImageScan.where(app_record_id: app.id, status: :pending).update_all(status: ImageScan.statuses[:skipped], updated_at: Time.current)
        ImageScan.create!(app_record: app, deploy: deploy, server_id: app.server_id, image_ref: ref, trigger: trigger)
      end
    rescue StandardError => e
      Rails.logger.warn("[ImageScans::Enqueue] #{app&.name}: #{e.class}: #{e.message}")
      nil
    end
  end
end
