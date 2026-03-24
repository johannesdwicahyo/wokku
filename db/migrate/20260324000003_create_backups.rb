class CreateBackups < ActiveRecord::Migration[8.1]
  def change
    create_table :backups do |t|
      t.references :database_service, null: false, foreign_key: true
      t.references :backup_destination, null: false, foreign_key: true
      t.string :s3_key, null: false
      t.string :status, default: "pending"
      t.bigint :size_bytes
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :backups, [:database_service_id, :created_at]
  end
end
