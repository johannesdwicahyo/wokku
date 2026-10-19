class AddVisitTrackingToAppRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :app_records, :last_request_at, :datetime
    add_column :app_records, :request_count_seen, :bigint
  end
end
