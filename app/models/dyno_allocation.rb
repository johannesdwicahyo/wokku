class DynoAllocation < ApplicationRecord
  belongs_to :app_record
  belongs_to :dyno_tier, optional: true

  validates :process_type, presence: true, uniqueness: { scope: :app_record_id }
  validates :count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :tier_or_shape
  validate :shape_on_grid, if: -> { cpu.present? || memory_mb.present? }
  # A shape wins over a tier, so a legacy tier change (scaling picker, API
  # dynos) that leaves a backfilled shape in place would be silently ignored.
  # Assigning a tier without touching the shape hands sizing back to the tier.
  # The builder (Resources::ApplyChange) always writes cpu/memory_mb itself.
  before_save :release_shape, if: -> { will_save_change_to_dyno_tier_id? && dyno_tier_id.present? && !will_save_change_to_cpu? && !will_save_change_to_memory_mb? }

  # Under Phase 4 invoice billing, container cost is bundled into the
  # user's monthly plan invoice — no per-allocation usage segments. The
  # ResourceUsage open/close/rewrite hooks were removed in 1.8 along
  # with the legacy daily-debit rail.

  def monthly_cost_cents
    count * dyno_tier&.monthly_price_cents.to_i
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

  # User-facing size string for the allocation, regardless of whether it's
  # backed by a legacy tier or a per-resource shape.
  def size_label
    return "sleeping" if sleeping?
    return DynoTier::DYNO_TIER_TO_BOX_SIZE[dyno_tier.name] || dyno_tier.name if shape.nil? && dyno_tier
    mem = memory_mb >= 1024 ? "#{(memory_mb / 1024.0).to_s.delete_suffix('.0')} GB" : "#{memory_mb} MB"
    "#{cpu.to_f.to_s.delete_suffix('.0')} vCPU · #{mem}"
  end

  private

  def release_shape
    self.cpu = self.memory_mb = nil
  end

  def tier_or_shape
    errors.add(:base, "needs a tier or a shape") if dyno_tier.nil? && (cpu.blank? || memory_mb.blank?)
  end

  def shape_on_grid
    Resources::Shape.new(cpu: cpu, memory_mb: memory_mb).errors.each { |e| errors.add(:base, e) }
  end
end
