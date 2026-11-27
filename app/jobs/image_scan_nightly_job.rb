# Queue a nightly scan for every app whose current image has no fresh scan.
class ImageScanNightlyJob < ApplicationJob
  queue_as :default

  FRESH_FOR = 20.hours

  def perform
    return unless Wokku.config.image_scans?

    fresh = ImageScan.where(status: :succeeded, created_at: FRESH_FOR.ago..).select(:app_record_id)
    AppRecord.where.not(server_id: nil).where.not(id: fresh).find_each do |app|
      deploy = app.releases.order(version: :desc).includes(:deploy).map(&:deploy).find { |d| d&.succeeded? }
      next unless deploy&.image_ref

      ImageScans::Enqueue.call(app: app, deploy: deploy, trigger: :nightly)
    end
  end
end
