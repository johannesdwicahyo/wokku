class CreateAlertMutes < ActiveRecord::Migration[8.1]
  def change
    create_table :alert_mutes, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :app_record, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :event
      t.datetime :expires_at
      t.timestamps
    end
    # NULL app/event mean "any"; COALESCE makes them compare equal so one
    # user has one row per (app, event) scope. (NULLS NOT DISTINCT needs PG15.)
    add_index :alert_mutes,
              "user_id, COALESCE(app_record_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(event, '')",
              unique: true, name: "index_alert_mutes_on_scope"
  end
end
