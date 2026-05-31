class CreateRequestSamples < ActiveRecord::Migration[8.1]
  def change
    create_table :request_samples, id: :uuid do |t|
      t.references :server,      null: false, foreign_key: true, type: :uuid
      t.references :app_record,  null: true,  foreign_key: true, type: :uuid
      t.datetime   :ts,          null: false
      t.string     :method,      limit: 8
      t.string     :path,        limit: 2048
      t.integer    :status
      t.integer    :response_time_ms
      t.bigint     :bytes_sent
      t.string     :remote_addr, limit: 64
      t.datetime   :ingested_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :request_samples, [ :app_record_id, :ts ],
              order: { ts: :desc }, name: "idx_req_samples_app_ts"
    add_index :request_samples, [ :ts ],
              order: { ts: :desc }, name: "idx_req_samples_ts" # for prune sweep
  end
end
