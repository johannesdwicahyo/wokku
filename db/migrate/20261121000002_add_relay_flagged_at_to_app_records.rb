class AddRelayFlaggedAtToAppRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :app_records, :relay_flagged_at, :datetime
  end
end
