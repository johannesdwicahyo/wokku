class ReconcileDynoUsageSegments < ActiveRecord::Migration[8.1]
  # Until today, ResourceUsage was written only at app creation and
  # never updated when a DynoAllocation's tier or count changed — so
  # switching Free → Basic left the segment at price=0, making billing
  # compute Rp 0 "so far today" for a paid dyno.
  #
  # For each current allocation: close any stale segment and open a
  # fresh one at the current rate, starting NOW. Historical billing is
  # forfeit (we have no tier-change history to reconstruct from), but
  # from the migration forward every change is captured by the new
  # DynoAllocation callbacks and the numbers line up.
  def up
    return unless defined?(DynoAllocation) && defined?(ResourceUsage)

    DynoAllocation.includes(:dyno_tier, app_record: {}).find_each do |alloc|
      app = alloc.app_record
      next unless app&.created_by_id

      ref = "AppRecord:#{alloc.app_record_id}:#{alloc.process_type}"
      # Close anything open under the new or the legacy key.
      ResourceUsage.where(resource_id_ref: [ ref, "AppRecord:#{alloc.app_record_id}" ], stopped_at: nil)
                   .update_all(stopped_at: Time.current)

      ResourceUsage.create!(
        user_id: app.created_by_id,
        resource_type: "container",
        resource_id_ref: ref,
        tier_name: alloc.dyno_tier.name,
        price_cents_per_hour: alloc.dyno_tier.price_cents_per_hour * alloc.count,
        started_at: Time.current,
        metadata: { app: app.name, process_type: alloc.process_type, count: alloc.count }
      )
    end
  end

  def down
    # no-op — these are ledger entries, not schema
  end
end
