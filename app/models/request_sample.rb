# One row per HTTP request, parsed from Dokku's nginx-proxy access log
# and shipped by Vector to `POST /api/v1/requests/ingest`. Powers the
# per-app monitor page at `/dashboard/apps/:id/monitor` after a rollup
# pass (see RequestAggregate).
#
# Samples retained 24h; aggregates retained indefinitely (small).
class RequestSample < ApplicationRecord
  belongs_to :server
  belongs_to :app_record, optional: true

  validates :ts, presence: true

  scope :for_app, ->(app) { where(app_record_id: app.id) }
  scope :since,   ->(t)   { where("ts >= ?", t) }
  scope :until_,  ->(t)   { where("ts <= ?", t) }
  scope :recent,  -> { order(ts: :desc) }
  scope :slow,    -> { order(response_time_ms: :desc) }
end
