class VitalsHourlyRollup < ApplicationRecord
  belongs_to :app_record

  validates :metric, inclusion: { in: VitalsEvent::METRICS }
  validates :bucketed_at, uniqueness: { scope: [ :app_record_id, :metric ] }

  scope :for_app, ->(app) { where(app_record: app) }
  scope :since,   ->(t)   { where("bucketed_at >= ?", t) }
  scope :asc_t,   ->      { order(bucketed_at: :asc) }

  # Returns { "LCP" => <rollup>, "CLS" => <rollup>, ... } — latest per metric.
  def self.latest_by_metric(app)
    sub = for_app(app)
            .select("DISTINCT ON (metric) *")
            .order(:metric, bucketed_at: :desc)
    sub.index_by(&:metric)
  end
end
