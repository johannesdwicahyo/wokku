# One row: the newest self-host release seen by UpdateCheckJob, and the
# version the admin was last emailed about (so each release mails once).
class CreateUpdateStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :update_statuses, id: :uuid do |t|
      t.string :latest_version
      t.string :notified_version
      t.datetime :checked_at
      t.timestamps
    end
  end
end
