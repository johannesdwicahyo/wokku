class CreatePushTickets < ActiveRecord::Migration[8.1]
  def change
    create_table :push_tickets do |t|
      t.references :device_token, null: false, foreign_key: true
      t.string :ticket_id, null: false
      t.string :status, default: "pending"
      t.datetime :checked_at
      t.timestamps
    end
    add_index :push_tickets, :ticket_id, unique: true
    add_index :push_tickets, :checked_at
  end
end
