# frozen_string_literal: true

module BackupsHelper
  # Formats a ServiceTier GFS policy hash into a short customer-facing
  # summary, e.g. {daily: 7, weekly: 4, monthly: 1} => "7 daily, 4 weekly,
  # 1 monthly backups". Zero-count buckets are omitted (basic's
  # {daily: 7, weekly: 0, monthly: 0} => "7 daily backups"). Returns nil
  # when every bucket is zero (shared_free) so callers can fall back to
  # tier-appropriate copy.
  def gfs_retention_summary(gfs)
    parts = %i[daily weekly monthly].filter_map do |bucket|
      count = gfs[bucket]
      "#{count} #{bucket}" if count.to_i.positive?
    end
    return nil if parts.empty?

    "#{parts.join(', ')} backups"
  end
end
