class CreateBackupDestinations < ActiveRecord::Migration[8.1]
  def change
    create_table :backup_destinations do |t|
      t.references :server, null: false, foreign_key: true, index: { unique: true }
      t.string :provider, default: "s3"
      t.string :endpoint_url
      t.string :bucket, null: false
      t.string :region, default: "us-east-1"
      t.string :access_key_id
      t.string :secret_access_key
      t.string :path_prefix, default: "wokku-backups"
      t.integer :retention_days, default: 30
      t.boolean :enabled, default: true
      t.timestamps
    end
  end
end
