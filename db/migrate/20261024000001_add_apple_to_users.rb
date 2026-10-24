class AddAppleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :apple_uid, :string
    add_column :users, :apple_refresh_token, :text
    add_column :users, :apple_token_client_id, :string
    add_index :users, :apple_uid, unique: true
  end
end
