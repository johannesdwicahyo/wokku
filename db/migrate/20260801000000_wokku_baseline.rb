# Baseline schema for fresh OSS installs. Pre-split installs (wokku-cloud
# dev/test/prod) always have the schema already — db:prepare loads
# db/structure.sql before migrations run — so this records its version and
# does nothing there. On a fresh self-host database it builds the full
# schema from the structure dump the exported repo ships at db/.
class WokkuBaseline < ActiveRecord::Migration[8.1]
  def up
    return if table_exists?(:users)

    dump = Wokku::Engine.root.join("db/structure.sql")
    unless dump.file?
      raise "wokku baseline: #{dump} missing — in the exported OSS repo the " \
            "structure dump ships at the repo root's db/; in the wokku-cloud " \
            "monorepo the schema comes from db:prepare and this never runs."
    end

    # The migrator pre-creates empty bookkeeping tables; the dump recreates
    # both (schema + PKs), so drop the empty ones first. The migrator
    # records THIS version into the recreated schema_migrations after up.
    drop_table :ar_internal_metadata, if_exists: true
    drop_table :schema_migrations, if_exists: true

    # Strip the dump's own schema_migrations inserts — this migration's
    # version is recorded by the migrator itself.
    sql = dump.read.gsub(/^INSERT INTO "?schema_migrations"?.*?;$/m, "")
    execute sql
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
