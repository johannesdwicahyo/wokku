class AddBundleColumnsToPlans < ActiveRecord::Migration[8.1]
  def change
    # Bundle sizes from the bundles spec. Each plan ships with 1 of each
    # (postgres, redis, minio) up to these caps. Sizes in MB (DB/Redis)
    # and GB (MinIO bucket) keep the integers readable.
    # Defaults match the Free tier so accidentally-Free apps don't
    # silently get a larger allocation.
    add_column :plans, :db_bundle_mb,    :integer, null: false, default: 100
    add_column :plans, :redis_bundle_mb, :integer, null: false, default: 25
    add_column :plans, :minio_bundle_gb, :integer, null: false, default: 1
  end
end
