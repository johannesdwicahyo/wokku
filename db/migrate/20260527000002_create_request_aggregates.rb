class CreateRequestAggregates < ActiveRecord::Migration[8.1]
  def change
    create_table :request_aggregates, id: :uuid do |t|
      t.references :app_record,   null: false, foreign_key: true, type: :uuid
      t.datetime   :bucket_start, null: false       # floor(ts, 5 min)
      t.integer    :req_count,    null: false, default: 0
      t.integer    :p50_ms
      t.integer    :p95_ms
      t.integer    :error_4xx,    null: false, default: 0
      t.integer    :error_5xx,    null: false, default: 0
      t.bigint     :bytes_sent_total, null: false, default: 0
      t.datetime   :created_at,   null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :request_aggregates, [ :app_record_id, :bucket_start ],
              unique: true, name: "idx_req_agg_app_bucket"
    add_index :request_aggregates, [ :bucket_start ],
              order: { bucket_start: :desc }, name: "idx_req_agg_bucket"
  end
end
