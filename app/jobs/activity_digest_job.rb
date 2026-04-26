class ActivityDigestJob < ApplicationJob
  queue_as :default

  # Runs once a day and records yesterday's chain-hash digest. Idempotent —
  # re-running recomputes + updates. Also back-fills any missing days in the
  # last 7, in case the scheduler missed a run (box reboot etc.).
  def perform
    today = Time.current.utc.to_date
    (1..7).map { |ago| today - ago }.sort.each do |d|
      next if d < first_activity_date
      ActivityDigest.record_for!(d)
    end
  end

  private

  def first_activity_date
    @first_activity_date ||= (Activity.order(:created_at).limit(1).pick(:created_at)&.utc&.to_date || Date.current)
  end
end
