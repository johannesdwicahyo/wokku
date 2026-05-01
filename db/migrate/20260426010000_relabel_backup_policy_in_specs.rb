class RelabelBackupPolicyInSpecs < ActiveRecord::Migration[8.1]
  # Tightens the spec.backups label so the addons UI reads grammatically:
  # "manual" → "manual backup", "auto-daily" → "auto-daily backup".
  def up
    execute <<~SQL
      UPDATE service_tiers
      SET spec = jsonb_set(spec, '{backups}', '"manual backup"'::jsonb),
          updated_at = NOW()
      WHERE service_type IN ('postgres', 'mysql', 'mongodb')
        AND spec->>'backups' = 'manual'
    SQL

    execute <<~SQL
      UPDATE service_tiers
      SET spec = jsonb_set(spec, '{backups}', '"auto-daily backup"'::jsonb),
          updated_at = NOW()
      WHERE service_type IN ('postgres', 'mysql', 'mongodb')
        AND spec->>'backups' = 'auto-daily'
    SQL
  end

  def down
    # No-op
  end
end
