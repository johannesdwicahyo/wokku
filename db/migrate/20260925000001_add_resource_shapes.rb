# Per-resource shapes (spec 2026-09-24): every process and dedicated
# datastore carries its own CPU/RAM(/disk). dyno_tier stays only for the
# free sleeping preset, so it becomes optional.
class AddResourceShapes < ActiveRecord::Migration[8.1]
  def change
    add_column :dyno_allocations, :cpu, :decimal, precision: 4, scale: 2, if_not_exists: true
    add_column :dyno_allocations, :memory_mb, :integer, if_not_exists: true
    change_column_null :dyno_allocations, :dyno_tier_id, true

    add_column :database_services, :cpu, :decimal, precision: 4, scale: 2, if_not_exists: true
    add_column :database_services, :memory_mb, :integer, if_not_exists: true
    add_column :database_services, :disk_gb, :integer, if_not_exists: true

    add_column :app_records, :volume_disk_gb, :integer, default: 0, null: false, if_not_exists: true
  end
end
