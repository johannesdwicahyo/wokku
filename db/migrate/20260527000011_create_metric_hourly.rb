class CreateMetricHourly < ActiveRecord::Migration[8.1]
  def change
    create_table :metric_hourly, id: :uuid do |t|
      t.references :app_record,  null: false, foreign_key: true, type: :uuid
      t.datetime   :hour_start,  null: false
      t.float      :avg_cpu_percent
      t.float      :max_cpu_percent
      t.bigint     :avg_memory_usage
      t.bigint     :max_memory_usage
      t.bigint     :memory_limit              # last-known limit; stable across an hour
      t.integer    :sample_count, null: false, default: 0
      t.datetime   :created_at,   null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :metric_hourly, [ :app_record_id, :hour_start ],
              unique: true, name: "idx_metric_hourly_app_hour"
    add_index :metric_hourly, [ :hour_start ],
              order: { hour_start: :desc }, name: "idx_metric_hourly_hour"
  end
end
