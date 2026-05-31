class CreateLogsAndServerIngestToken < ActiveRecord::Migration[8.1]
  def change
    # Per-server pre-shared token for the Vector → wokku-cloud log
    # ingest endpoint. Rotated by re-running the provisioning script.
    add_column :servers, :ingest_token, :string

    create_table :logs, id: :uuid do |t|
      t.references :server,     null: false, foreign_key: true, type: :uuid
      t.references :app_record, foreign_key: true, type: :uuid # nullable — container may not map to a known app
      t.string     :container, null: false           # e.g. "myapp.web.1"
      t.datetime   :ts,        null: false           # log line timestamp (from Vector)
      t.string     :level                            # parsed: info | warn | error | debug | ""
      t.text       :line,      null: false           # the actual log line content
      t.datetime   :ingested_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :logs, [ :app_record_id, :ts ], order: { ts: :desc }, name: "idx_logs_app_ts"
    add_index :logs, [ :server_id, :ts ], order: { ts: :desc }, name: "idx_logs_server_ts"
    add_index :logs, [ :ts ], order: { ts: :desc }, name: "idx_logs_ts" # for prune
    # Full-text search: ILIKE will be fine for v1; if it gets slow we can
    # add a tsvector column + GIN index later. Don't pre-optimise.
  end
end
