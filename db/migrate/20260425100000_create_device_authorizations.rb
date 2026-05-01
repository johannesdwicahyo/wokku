class CreateDeviceAuthorizations < ActiveRecord::Migration[8.1]
  def change
    create_table :device_authorizations do |t|
      t.string :device_code, null: false
      t.string :user_code, null: false
      t.string :status, null: false, default: "pending"
      t.references :user, foreign_key: true
      t.references :api_token, foreign_key: true
      t.datetime :expires_at, null: false
      t.datetime :last_polled_at
      t.text :plain_token_payload
      t.timestamps
    end

    add_index :device_authorizations, :device_code, unique: true
    add_index :device_authorizations, :user_code, unique: true
    add_index :device_authorizations, :status
  end
end
