class AddSshAlertedAtToServers < ActiveRecord::Migration[8.1]
  def change
    # Set when the SSH-down page goes out; cleared (with a recovery page) when SSH works again.
    add_column :servers, :ssh_alerted_at, :datetime
  end
end
