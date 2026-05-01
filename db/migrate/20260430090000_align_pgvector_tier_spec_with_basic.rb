class AlignPgvectorTierSpecWithBasic < ActiveRecord::Migration[8.1]
  # First seed of basic-pgvector accidentally over-specced it (256 MB /
  # 5 GB / 50 conn) which made it more generous than even the
  # Performance tier (512 MB / 16 GB / 40 conn) at a fraction of the
  # price. Align the caps to match Basic exactly — only the Docker
  # image differs. Existing addons keep running on whatever resources
  # Dokku already gave them; this only changes what new addons get.
  def up
    return unless defined?(ServiceTier)
    tier = ServiceTier.find_by(name: "basic-pgvector", service_type: "postgres")
    return unless tier
    tier.update!(spec: {
      memory_mb: 128, storage_gb: 1, connections: 10,
      backups: "manual backup", backup_retention: 2,
      image: "pgvector/pgvector", image_version: "pg16",
      extensions: %w[vector],
      notes: "Postgres 16 + pgvector. CREATE EXTENSION vector after provisioning."
    })
  end

  def down
    # No reliable inverse; the previous over-spec was a bug, not a state
    # we want to be able to restore.
  end
end
