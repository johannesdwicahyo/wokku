class DynoAllocation < ApplicationRecord
  belongs_to :app_record
  belongs_to :dyno_tier, optional: true

  validates :process_type, presence: true, uniqueness: { scope: :app_record_id }
  validates :count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :tier_or_shape
  validate :shape_on_grid, if: -> { cpu.present? || memory_mb.present? }

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

  # Per-resource shape (spec 2026-09-24); nil for tier-only rows (legacy,
  # and the free sleeping preset which stays a tier).
  def shape
    Resources::Shape.new(cpu: cpu, memory_mb: memory_mb) if cpu.present? && memory_mb.present?
  end

  def effective_cpu = cpu.present? ? cpu.to_f : dyno_tier&.cpu_shares&.to_f
  def effective_memory_mb = memory_mb.presence || dyno_tier&.memory_mb&.to_i
  def sleeping? = shape.nil? && !!dyno_tier&.sleeps

  private

  def tier_or_shape
    errors.add(:base, "needs a tier or a shape") if dyno_tier.nil? && (cpu.blank? || memory_mb.blank?)
  end

  def shape_on_grid
    Resources::Shape.new(cpu: cpu, memory_mb: memory_mb).errors.each { |e| errors.add(:base, e) }
  end
end
