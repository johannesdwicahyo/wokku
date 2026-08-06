# One row per (database, collection-time) sample. Written by
# DatabaseStatsCollectorJob every 5 min via recurring.yml.
# Powers the brutalist Sumopod-style monitor page at
# /dashboard/databases/:id/monitor.
class DatabaseStatsSnapshot < ApplicationRecord
  belongs_to :database_service

  scope :recent,  -> { order(recorded_at: :desc) }
  scope :since,   ->(t) { where("recorded_at >= ?", t) }
  scope :ok,      -> { where(collection_error: nil) }

  def ok?
    collection_error.blank?
  end
end
