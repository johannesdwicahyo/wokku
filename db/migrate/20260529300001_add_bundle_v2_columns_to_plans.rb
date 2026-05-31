class AddBundleV2ColumnsToPlans < ActiveRecord::Migration[8.1]
  # Bundle v2 (founder decision 2026-05-29 — see memory
  # project_bundle_v2_locked_spec.md): every box ships the full shared
  # backend stack at create time. Dedicated Pg/Redis are the only
  # upgrade lever. No paid extras anywhere.
  #
  # This migration adds the size + slot columns the new model needs.
  # Defaults are zero so existing seed data stays valid until the
  # SeedCanonicalPlans pass repopulates them.
  def change
    # Per-tenant size caps for the shared services (read by each
    # plugin's check-quotas cron).
    add_column :plans, :shared_pg_mb_per_tenant,          :integer, null: false, default: 50
    add_column :plans, :shared_redis_mb_per_tenant,       :integer, null: false, default: 10
    add_column :plans, :shared_memcached_mb_per_tenant,   :integer, null: false, default: 16
    add_column :plans, :shared_rabbitmq_msg_per_tenant,   :integer, null: false, default: 10_000
    add_column :plans, :shared_meilisearch_mb_per_tenant, :integer, null: false, default: 50

    # Dedicated upgrade slots (per workspace). When a user "upgrades"
    # a box's shared Pg/Redis to dedicated, one slot is consumed; the
    # shared tenant is dropped and a real dokku-postgres / dokku-redis
    # container takes over.
    add_column :plans, :dedicated_pg_slots,               :integer, null: false, default: 0
    add_column :plans, :dedicated_pg_size_mb,             :integer, null: false, default: 0
    add_column :plans, :dedicated_redis_slots,            :integer, null: false, default: 0
    add_column :plans, :dedicated_redis_size_mb,          :integer, null: false, default: 0

    # minio_bundle_gb already exists from the earlier phase 4 work;
    # carries over unchanged as the workspace-wide MinIO cap.
  end
end
