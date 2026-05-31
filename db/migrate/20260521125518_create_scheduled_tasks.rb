class CreateScheduledTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :scheduled_tasks, id: :uuid do |t|
      t.references :app_record, null: false, foreign_key: true, type: :uuid
      t.text    :command,     null: false
      t.string  :schedule,    null: false
      t.string  :description
      t.boolean :enabled,     null: false, default: true
      t.timestamps
    end
    add_index :scheduled_tasks, [:app_record_id, :schedule]
  end
end
