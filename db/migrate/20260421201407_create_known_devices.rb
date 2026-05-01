class CreateKnownDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :known_devices do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :ip,               null: false
      t.string  :user_agent_hash,  null: false
      t.string  :user_agent_label
      t.datetime :first_seen_at,   null: false
      t.datetime :last_seen_at,    null: false
      t.timestamps

      t.index [ :user_id, :ip, :user_agent_hash ], unique: true, name: "index_known_devices_on_user_ip_ua"
    end
  end
end
