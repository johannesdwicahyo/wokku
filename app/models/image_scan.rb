# One Trivy scan of an app's deployed image, run by wokkud on the app's host.
# Informational only: a scan never affects a deploy. Stores severity counts and
# at most MAX_FINDINGS findings; raw scanner output is never kept.
class ImageScan < ApplicationRecord
  MAX_FINDINGS = 50
  ERROR_CODES = %w[pull_failed db_unavailable timeout oom parse_failed image_missing disk_full].freeze
  KEEP_PER_APP = 10

  belongs_to :app_record
  belongs_to :deploy, optional: true
  belongs_to :server

  enum :trigger, { deploy: 0, nightly: 1 }, prefix: :via
  enum :status, { pending: 0, claimed: 1, succeeded: 2, failed: 3, skipped: 4 }

  # What the app page shows for the CURRENT image only (superseded images'
  # scans are history): the newest succeeded scan, else the newest live/failed
  # one. One query. nil when the image has never been scanned.
  def self.for_image(app_record, image_ref)
    return if image_ref.blank?
    # findings jsonb is not loaded here (overview); the findings page reloads it.
    scans = where(app_record: app_record, image_ref: image_ref).where.not(status: :skipped)
      .select(column_names - %w[findings]).order(id: :desc).limit(KEEP_PER_APP).to_a
    scans.find(&:succeeded?) || scans.first
  end
end
