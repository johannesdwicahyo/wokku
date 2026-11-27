class AddNotifiedAtToImageScans < ActiveRecord::Migration[8.1]
  def change
    add_column :image_scans, :notified_at, :datetime
  end
end
