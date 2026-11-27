class ImageScanJanitorJob < ApplicationJob
  queue_as :default

  REAP_AFTER = 15.minutes

  def perform
    ImageScan.claimed.where(claimed_at: ...REAP_AFTER.ago).update_all(
      status: ImageScan.statuses[:failed], error_code: "timeout", error: "scanner never reported",
      finished_at: Time.current, updated_at: Time.current
    )
    ImageScan.skipped.delete_all
    stale = ImageScan.where.not(status: :skipped).select("id, row_number() OVER (PARTITION BY app_record_id ORDER BY created_at DESC, id DESC) AS rn")
    ImageScan.where(id: ImageScan.from(stale, :ranked).where("rn > ?", ImageScan::KEEP_PER_APP).select(:id))
             .where.not(status: %i[pending claimed]).delete_all
  end
end
