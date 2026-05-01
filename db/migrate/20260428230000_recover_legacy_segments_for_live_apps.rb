class RecoverLegacySegmentsForLiveApps < ActiveRecord::Migration[8.1]
  # The earlier CloseOrphanResourceUsages migration was too aggressive —
  # it closed every "legacy" `AppRecord:<id>` segment unconditionally on
  # the assumption that DynoAllocation-shaped segments existed alongside
  # them. For apps that pre-date DynoAllocation (or never had ps:scale
  # run), the legacy segment was the *only* segment tracking their
  # usage. Closing it removed them from the Running resources table.
  #
  # This recovery walks closed legacy segments and reopens any whose
  # AppRecord still exists. We restore stopped_at to NULL — the missing
  # hours between the bad close and now are tiny (less than a day) and
  # not worth the complication of a backfill via started_at adjustment.
  def up
    sql = <<~SQL
      UPDATE resource_usages
      SET stopped_at = NULL
      WHERE stopped_at IS NOT NULL
        AND resource_id_ref ~ '^AppRecord:[^:]+$'
        AND SUBSTRING(resource_id_ref FROM 'AppRecord:(.+)') IN (
          SELECT id::text FROM app_records
        )
    SQL
    rows = connection.execute(sql).cmd_tuples
    say "Reopened #{rows} legacy segments for live apps"
  end

  def down
    # No reliable inverse — closed segments are billing history.
  end
end
