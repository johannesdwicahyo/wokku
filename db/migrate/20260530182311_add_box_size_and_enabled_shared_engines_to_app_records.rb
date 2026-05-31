# Bundle v2 prep — adds the box-model user-facing fields to app_records.
#
# - box_size: one of sleeping / small / medium / large / xlarge. Eventually
#   replaces user-facing reliance on dyno_tier_id (the latter stays as
#   internal plumbing mapping size → CPU/memory specs).
# - enabled_shared_engines: which of the 5 shared engines (postgres,
#   redis, memcached, rabbitmq, meilisearch) the box has attached. User-
#   pick per box at creation; editable from box settings. Replaces the
#   2026-05-29 spec's "auto-attach all 5".
#
# Backfill:
# - box_size derived from existing dyno_tier_id via the BOX_SIZE_FOR map.
# - enabled_shared_engines derived from existing AppDatabase rows joined
#   to shared DatabaseService rows (covers existing apps with shared
#   tenants attached pre-Bundle v2).
#
# All dormant until Phase 7 flips BUNDLE_V2_ENABLED. No code path reads
# these columns yet.
class AddBoxSizeAndEnabledSharedEnginesToAppRecords < ActiveRecord::Migration[8.1]
  BOX_SIZE_FOR = {
    "free"           => "sleeping",
    "basic"          => "small",
    "standard"       => "medium",
    "performance"    => "large",
    "performance-2x" => "xlarge"
  }.freeze

  def up
    add_column :app_records, :box_size, :string
    add_column :app_records, :enabled_shared_engines, :string, array: true, default: [], null: false
    add_index  :app_records, :box_size

    # Backfill box_size from the matching DynoTier name. DynoTier is
    # joined via dyno_allocations (web process is primary, matches the
    # pattern in scaling_controller.rb + app_overview_component.rb).
    BOX_SIZE_FOR.each do |tier_name, box_size|
      execute <<~SQL
        UPDATE app_records ar
        SET    box_size = #{quote(box_size)}
        FROM   dyno_allocations da
        JOIN   dyno_tiers dt ON dt.id = da.dyno_tier_id
        WHERE  da.app_record_id = ar.id
          AND  da.process_type = 'web'
          AND  dt.name = #{quote(tier_name)}
      SQL
    end

    # Backfill enabled_shared_engines from existing AppDatabase → DatabaseService
    # joins where the database is shared. Aggregates distinct service_types.
    execute <<~SQL
      UPDATE app_records ar
      SET    enabled_shared_engines = sub.engines
      FROM (
        SELECT ad.app_record_id, array_agg(DISTINCT ds.service_type ORDER BY ds.service_type) AS engines
        FROM   app_databases ad
        JOIN   database_services ds ON ds.id = ad.database_service_id
        WHERE  ds.shared = true
        GROUP BY ad.app_record_id
      ) sub
      WHERE ar.id = sub.app_record_id
    SQL
  end

  def down
    remove_index  :app_records, :box_size
    remove_column :app_records, :enabled_shared_engines
    remove_column :app_records, :box_size
  end
end
