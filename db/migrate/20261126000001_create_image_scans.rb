class CreateImageScans < ActiveRecord::Migration[8.1]
  def change
    create_table :image_scans, id: :uuid do |t|
      t.references :app_record, type: :uuid, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :deploy, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :server, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :image_ref, null: false
      t.integer :trigger, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.jsonb :counts, null: false, default: {}
      t.jsonb :findings, null: false, default: []
      t.string :scanner_version
      t.datetime :db_updated_at
      t.string :error_code
      t.string :error
      t.datetime :claimed_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :image_scans, [ :app_record_id, :created_at ], order: { created_at: :desc }, name: "index_image_scans_on_app_and_created_at"
    # status 0 = pending: one queued scan per app (a claimed one may coexist with the next)
    add_index :image_scans, :app_record_id, unique: true, where: "status = 0", name: "index_image_scans_one_active_per_app"
    add_index :image_scans, [ :server_id, :status ]
  end
end
