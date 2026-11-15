class CreateStorageBackupRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :storage_backup_runs, id: :uuid do |t|
      t.references :server, null: false, foreign_key: true, type: :uuid
      t.string :kind, null: false
      t.string :status, null: false
      t.bigint :objects
      t.bigint :bytes
      t.integer :duration_s
      t.text :error
      t.timestamps
    end
    add_index :storage_backup_runs, [ :server_id, :kind, :created_at ]
  end
end
