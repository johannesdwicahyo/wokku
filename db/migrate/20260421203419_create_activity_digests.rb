class CreateActivityDigests < ActiveRecord::Migration[8.1]
  # Daily tamper-evidence record over the activities table. Each row chains
  # to the previous day's hash, so any edit to a historical activity (even
  # one that bypasses the append-only trigger) surfaces as a broken chain.
  def change
    create_table :activity_digests do |t|
      t.date     :date,          null: false
      t.integer  :row_count,     null: false, default: 0
      t.string   :chain_hash,    null: false
      t.string   :prev_hash
      t.integer  :min_activity_id
      t.integer  :max_activity_id
      t.timestamps

      t.index :date, unique: true
    end
  end
end
