class AddPendingRevokeAccessKeyToObjectStorageBuckets < ActiveRecord::Migration[8.1]
  def change
    add_column :object_storage_buckets, :pending_revoke_access_key, :string
  end
end
