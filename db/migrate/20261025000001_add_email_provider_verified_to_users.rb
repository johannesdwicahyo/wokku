class AddEmailProviderVerifiedToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :email_provider_verified, :boolean, null: false, default: false
    execute "UPDATE users SET email_provider_verified = TRUE WHERE provider IS NOT NULL OR role = 1"
  end

  def down
    remove_column :users, :email_provider_verified
  end
end
