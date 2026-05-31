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
      client = Dokku::Client.new(preview.server)
      Dokku::Apps.new(client).stop(preview.name)
      preview.update!(status: :stopped)
    rescue StandardError => e
      Rails.logger.warn("Preview::IdleSweeper sleep failed for #{preview.name}: #{e.message}")
    end
  end
end
