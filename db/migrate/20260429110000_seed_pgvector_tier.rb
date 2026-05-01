class SeedPgvectorTier < ActiveRecord::Migration[8.1]
  # Adds a Postgres + pgvector tier. Same price as the stock Basic
  # tier (Rp 15k/mo); pgvector is free and the extra image size is
  # marginal. Idempotent — safe to rerun.
  def up
    return unless defined?(ServiceTier)
    ServiceTier.find_or_create_by!(name: "basic-pgvector", service_type: "postgres") do |t|
      t.monthly_price_cents   = 100 # Rp 15,000/mo, same as Basic
      t.price_cents_per_hour  = 100.0 / 720.0
      t.spec = {
        memory_mb: 256,
        storage_gb: 5,
        connections: 50,
        image: "pgvector/pgvector",
        image_version: "pg16",
        extensions: %w[vector],
        notes: "Postgres 16 with the pgvector extension preinstalled. Run CREATE EXTENSION vector once after the addon is provisioned."
      }
      t.available = true
    end
  end

  def down
    return unless defined?(ServiceTier)
    ServiceTier.where(name: "basic-pgvector", service_type: "postgres").destroy_all
  end
end
