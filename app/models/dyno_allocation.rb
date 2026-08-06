class DynoAllocation < ApplicationRecord
  belongs_to :app_record
  belongs_to :dyno_tier

  validates :process_type, presence: true, uniqueness: { scope: :app_record_id }
  validates :count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Under Phase 4 invoice billing, container cost is bundled into the
  # user's monthly plan invoice — no per-allocation usage segments. The
  # ResourceUsage open/close/rewrite hooks were removed in 1.8 along
  # with the legacy daily-debit rail.

  def monthly_cost_cents
    count * dyno_tier.monthly_price_cents.to_i
  end

  def resource_id_ref
    "AppRecord:#{app_record_id}:#{process_type}"
  end
end
