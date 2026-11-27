# Queue a nightly scan for every app whose current image has no fresh scan.
class ImageScanNightlyJob < ApplicationJob
  queue_as :default

  FRESH_FOR = 20.hours

  def perform
    return unless Wokku.config.image_scans?

    fresh = ImageScan.where(status: :succeeded, created_at: FRESH_FOR.ago..).pluck(:app_record_id, :image_ref).to_set
    # Current deploy per app = newest release whose deploy succeeded (one
    # query); if it has no image_ref the app is skipped, not rolled back.
    current = Release.joins(:deploy).where(deploys: { status: Deploy.statuses[:succeeded] })
                     .select("DISTINCT ON (releases.app_record_id) releases.app_record_id, deploys.id AS deploy_id, deploys.image_ref AS ref")
                     .order("releases.app_record_id, releases.version DESC")
    apps = AppRecord.where.not(server_id: nil).index_by(&:id)
    current.each do |row|
      next if row.ref.blank? || fresh.include?([ row.app_record_id, row.ref ])
      app = apps[row.app_record_id] or next

      ImageScans::Enqueue.call(app: app, deploy: Deploy.find(row.deploy_id), trigger: :nightly)
    end
  end
end
