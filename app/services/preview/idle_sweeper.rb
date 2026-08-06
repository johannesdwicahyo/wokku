module Preview
  class IdleSweeper
    SLEEP_AFTER   = 7.days
    DESTROY_AFTER = 30.days

    def self.sweep
      # Destroy first so previously-stopped previews that have aged into
      # destroy territory get torn down rather than re-stopped.
      AppRecord.preview_idle_for(DESTROY_AFTER).find_each do |preview|
        Preview::Destroyer.new(preview).call
      end

      AppRecord.preview_idle_for(SLEEP_AFTER)
               .where.not(status: :stopped)
               .find_each do |preview|
        sleep_one(preview)
      end
    end

    def self.sleep_one(preview)
      Lifecycle::Ops.converge!(preview, formation: Lifecycle::Ops.stop_formation(preview), allow_empty: true)
      preview.update!(status: :stopped)
    rescue Lifecycle::Ops::Failed, Lifecycle::Ops::Timeout, Lifecycle::Ops::Busy, ArgumentError, ActiveRecord::RecordNotUnique => e
      # Busy: same live-op race Lifecycle::Ops.remove_if_flagged! rescues (a
      # pending/claimed op already exists for this app) — issue! now converts
      # that collision to Busy itself; RecordNotUnique stays for belt-and-
      # suspenders. One racing preview must not abort the whole sweep's find_each.
      Rails.logger.warn("Preview::IdleSweeper sleep failed for #{preview.name}: #{e.message}")
    end
  end
end
