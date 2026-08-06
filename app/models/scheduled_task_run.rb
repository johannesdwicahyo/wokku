class ScheduledTaskRun < ApplicationRecord
  EXCERPT_BYTES = 16_384
  RETENTION = 30.days

  belongs_to :scheduled_task

  # .scrub after byteslice: truncating raw bytes can split a multibyte UTF-8
  # char mid-sequence, which Postgres rejects outright — losing the whole
  # run row (not just the excerpt tail). scrub repairs the dangling bytes.
  before_save { self.log_excerpt = log_excerpt&.byteslice(0, EXCERPT_BYTES)&.scrub }

  def self.prune!
    where(created_at: ...RETENTION.ago).delete_all
  end
end
