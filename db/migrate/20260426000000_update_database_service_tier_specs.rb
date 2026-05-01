class UpdateDatabaseServiceTierSpecs < ActiveRecord::Migration[8.1]
  # Re-shape postgres/mysql/mongodb tier specs to include memory_mb,
  # tighten connection caps, and standardize backup retention. The seed
  # file is the source of truth for fresh installs; this migration
  # forces existing installs into the same shape.
  TIER_SPECS = {
    "basic"       => { memory_mb: 128, storage_gb: 1,  connections: 10, backups: "manual backup",     backup_retention: 2 },
    "standard"    => { memory_mb: 256, storage_gb: 8,  connections: 20, backups: "auto-daily backup", backup_retention: 5 },
    "performance" => { memory_mb: 512, storage_gb: 16, connections: 40, backups: "auto-daily backup", backup_retention: 10 }
  }.freeze

  DB_TYPES = %w[postgres mysql mongodb].freeze

  def up
    DB_TYPES.each do |db_type|
      TIER_SPECS.each do |name, spec|
        execute(
          ActiveRecord::Base.sanitize_sql_array([
            "UPDATE service_tiers SET spec = ?::jsonb, updated_at = NOW() WHERE name = ? AND service_type = ?",
            spec.to_json, name, db_type
          ])
        )
      end
    end
  end

  def down
    # No-op: previous spec shapes weren't versioned; reverting is a manual exercise.
  end
end
