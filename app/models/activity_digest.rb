class ActivityDigest < ApplicationRecord
  # One row per UTC calendar day. chain_hash is computed over (prev_hash +
  # every activity row from that day, serialized canonically). Any future
  # tampering with a past day's activities or with a digest row itself will
  # break the chain that follows.
  #
  # NOTE: activity_digests is not itself append-only. We rely on the
  # chain-hash property: if an attacker rewrites a digest, the next day's
  # hash (which mixed in their rewritten one) is still what was originally
  # stored, so a checksum of chain_hash || activities reveals the tamper.

  validates :date, presence: true, uniqueness: true
  validates :chain_hash, presence: true

  # Compute the chain hash for a given UTC date. Pure function — does not
  # touch the DB except to read activities + the previous digest.
  def self.compute_for(date)
    prev = where("date < ?", date).order(:date).last
    prev_hash = prev&.chain_hash.to_s

    activities = Activity.where("created_at >= ? AND created_at < ?",
                                date.beginning_of_day, date.next_day.beginning_of_day)
                         .order(:id)

    hash = Digest::SHA256.new
    hash.update(prev_hash)
    min_id = nil
    max_id = nil
    count = 0
    activities.find_each(batch_size: 500) do |a|
      count += 1
      min_id ||= a.id
      max_id = a.id
      hash.update([
        a.id, a.created_at.iso8601(6), a.action, a.user_id, a.team_id,
        a.target_type, a.target_id, a.target_name, a.metadata.to_json
      ].join("\x1f"))
    end

    {
      date: date,
      row_count: count,
      chain_hash: hash.hexdigest,
      prev_hash: prev_hash.presence,
      min_activity_id: min_id,
      max_activity_id: max_id
    }
  end

  # Persist (or upsert) the digest row for `date`.
  def self.record_for!(date)
    attrs = compute_for(date)
    existing = find_by(date: date)
    if existing
      existing.update!(attrs.except(:date))
      existing
    else
      create!(attrs)
    end
  end
end
