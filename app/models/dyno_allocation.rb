class DynoAllocation < ApplicationRecord
  belongs_to :app_record
  belongs_to :dyno_tier

  validates :process_type, presence: true, uniqueness: { scope: :app_record_id }
  validates :count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def monthly_cost_cents
    count * dyno_tier.price_cents_per_month
  end
end
