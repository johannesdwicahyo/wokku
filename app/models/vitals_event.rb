class VitalsEvent < ApplicationRecord
  METRICS = %w[CLS LCP INP FCP TTFB].freeze

  belongs_to :app_record

  validates :metric, inclusion: { in: METRICS }
  validates :value_ms, numericality: { greater_than_or_equal_to: 0 }
  validate :value_ms_is_finite

  scope :since,      ->(t) { where("received_at >= ?", t) }
  scope :older_than, ->(t) { where("received_at < ?", t) }

  private

  def value_ms_is_finite
    return if value_ms.nil?
    errors.add(:value_ms, "must be finite") unless value_ms.finite?
  end
end
