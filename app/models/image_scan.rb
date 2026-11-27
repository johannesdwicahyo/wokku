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
end
