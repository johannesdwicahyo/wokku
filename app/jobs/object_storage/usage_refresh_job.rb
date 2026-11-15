module ObjectStorage
  # Hourly: one usage call, update every bucket, mail once on crossing 80%.
  class UsageRefreshJob < ApplicationJob
    queue_as :default

    def perform
      return unless Wokku.config.object_storage?
      usage = Client.new.usage
      ObjectStorageBucket.find_each do |b|
        b.used_bytes = usage.fetch(b.name, 0)
        b.used_at = Time.current
        if b.near_quota?
          if b.warned_at.nil?
            b.warned_at = Time.current
            ObjectStorageMailer.near_quota(b).deliver_later
          end
        else
          b.warned_at = nil
        end
        b.save!
      end
    end
  end
end
