class CreateAppTransfers < ActiveRecord::Migration[8.1]
  def change
    create_table :app_transfers, id: :uuid do |t|
      t.references :app_record, null: false, foreign_key: true,                       type: :uuid
      t.references :from_user,  null: false, foreign_key: { to_table: :users }, type: :uuid
      t.references :to_user,    null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string     :status,     null: false, default: "pending"
      t.datetime   :expires_at, null: false
      t.datetime   :accepted_at
      t.datetime   :declined_at
      t.datetime   :cancelled_at
      t.text       :note
      t.timestamps
    end

    add_index :app_transfers, [ :app_record_id, :status ]
    add_index :app_transfers, [ :to_user_id, :status ]
  end
end
