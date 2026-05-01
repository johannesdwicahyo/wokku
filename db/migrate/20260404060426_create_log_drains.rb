class CreateLogDrains < ActiveRecord::Migration[8.1]
  def change
    create_table :log_drains do |t|
      t.references :app_record, null: false, foreign_key: true
      t.string :url, null: false
      t.string :drain_type, default: "syslog"

      t.timestamps
    end
  end
end
