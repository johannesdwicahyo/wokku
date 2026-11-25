# Composite index serves CpuSparks (per-app, time-bounded); the single-column
# index is its prefix, so it goes.
class IndexMetricsOnAppRecordIdRecordedAt < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :metrics, [ :app_record_id, :recorded_at ], algorithm: :concurrently
    remove_index :metrics, :app_record_id, algorithm: :concurrently
  end

  def down
    add_index :metrics, :app_record_id, algorithm: :concurrently
    remove_index :metrics, [ :app_record_id, :recorded_at ], algorithm: :concurrently
  end
end
