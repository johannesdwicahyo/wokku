class CreateObjectStorageBuckets < ActiveRecord::Migration[8.1]
  def change
    create_table :object_storage_buckets, id: :uuid do |t|
      t.references :app_record, foreign_key: { on_delete: :nullify }, type: :uuid, index: { unique: true }
      t.references :team, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :access_key, null: false
      t.text :secret_key, null: false
      t.integer :quota_gb, null: false
      t.bigint :used_bytes, null: false, default: 0
      t.datetime :used_at
      t.datetime :warned_at
      t.string :status, null: false, default: "provisioning"
      t.text :last_error
      t.timestamps
    end
    add_index :object_storage_buckets, :name, unique: true
  end
end
