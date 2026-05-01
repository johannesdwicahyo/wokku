class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :app_record, null: true, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.integer :channel
      t.json :events
      t.json :config

      t.timestamps
    end
  end
end
