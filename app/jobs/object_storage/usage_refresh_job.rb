module ObjectStorage
  # Hourly: retry stuck deletions, then one usage call, update every bucket,
  # mail once on crossing 80%.
  class UsageRefreshJob < ApplicationJob
    queue_as :default

    def perform
      return unless Wokku.config.object_storage?
      sweep_deletions
      sweep_pending_revokes
      usage = Client.new.usage
      ObjectStorageBucket.find_each do |b|
        # RustFS's scanner reports nothing right after a restart: keep the last value.
        next unless usage.key?(b.name)
        b.used_bytes = usage[b.name]
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

    private

    # DeprovisionJob gives up after 5 attempts; a `deleting` row or one whose
    # app is gone (Destroyer failure) would otherwise stay forever.
    def sweep_deletions
      ObjectStorageBucket.where(status: "deleting").or(ObjectStorageBucket.where(app_record_id: nil))
        .pluck(:id).each { |id| DeprovisionJob.perform_later(id) }
    end

    # RotateJob gives up after 3 attempts; a rotated-out key must not stay valid.
    # A retry with a pending key only revokes it (no new key pair).
    def sweep_pending_revokes
      ObjectStorageBucket.where(status: "active").where.not(pending_revoke_access_key: nil)
        .pluck(:id).each { |id| RotateJob.perform_later(id) }
    end
  end
end
