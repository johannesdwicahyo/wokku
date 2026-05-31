class CreateDatabaseStatsSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :database_stats_snapshots, id: :uuid do |t|
      t.references :database_service, null: false, foreign_key: true, type: :uuid
      t.datetime   :recorded_at,      null: false
      t.integer    :active_connections
      t.integer    :max_connections
      t.bigint     :db_size_bytes
      t.float      :cache_hit_ratio        # 0.0..1.0 for postgres heap_blks_hit / total
      t.jsonb      :top_queries, default: [] # pg_stat_statements rows
      t.jsonb      :raw_info, default: {}    # redis INFO blocks, etc.
      t.string     :collected_via            # "postgres" | "redis" — type marker
      t.string     :collection_error         # set when SSH/exec failed; null on success
      t.datetime   :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :database_stats_snapshots, [ :database_service_id, :recorded_at ],
              order: { recorded_at: :desc }, name: "idx_db_stats_svc_recorded"
    add_index :database_stats_snapshots, [ :recorded_at ],
              order: { recorded_at: :desc }, name: "idx_db_stats_recorded" # for prune
  end
end
