class DynoTier < ApplicationRecord
  HOURS_PER_MONTH = 720

  # Box-size vocabulary ↔ tier-name mapping (engine-owned since the P2
  # rider cleanup; Plan aliases these for cloud back-compat). box_size is
  # the user-facing concept, DynoTier the CPU/memory plumbing.
  BOX_SIZE_TO_DYNO_TIER = {
    "sleeping" => "free",
    "small"    => "basic",
    "medium"   => "standard",
    "large"    => "performance",
    "xlarge"   => "performance-2x"
  }.freeze
  DYNO_TIER_TO_BOX_SIZE = BOX_SIZE_TO_DYNO_TIER.invert.freeze

  has_many :dyno_allocations

  validates :name, presence: true, uniqueness: true
  validates :memory_mb, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :cpu_shares, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :price_cents_per_hour, numericality: { greater_than_or_equal_to: 0 }
  validates :price_cents_per_month,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :paid, -> { where(sleeps: false) }
  scope :available, -> { all }

  def free?
    monthly_price_cents.to_i == 0
  end

  # The user-facing box size for this tier, derived from the tier name via
  # the canonical map — NOT the `size_key` DB column, which was backfilled by
  # memory-MB ranges (free→small, performance→medium, performance-2x→large)
  # and is misaligned with Plan.box_quotas' five-size vocabulary. Both quota
  # enforcement (PlanEnforceable#current_box_count) and the dashboard read
  # this, so deriving from the name keeps them in sync and unable to drift.
  # Unknown/custom tier names (only test/bespoke tiers — all prod tiers use
  # the canonical names) fall back to a memory-MB bucket matching the
  # canonical tier sizes (256→sleeping, 512→small, 1024→medium, 2048→large).
  def size_key
    DYNO_TIER_TO_BOX_SIZE[name] || memory_size_key
  end

  def memory_size_key
    case memory_mb.to_i
    when 0..256     then "sleeping"
    when 257..512   then "small"
    when 513..1024  then "medium"
    when 1025..2048 then "large"
    else                 "xlarge"
    end
  end
  private :memory_size_key

  # Tiers under 1.0 vCPU share the host CPU scheduler with other
  # containers on the box (no dedicated core). For UI purposes these
  # render as "Shared vCPU" because exposing fractional vCPU numbers
  # to end users is misleading — the actual burst behavior depends on
  # neighbor load rather than the exact share.
  def shared_vcpu?
    cpu_shares.to_f < 1.0
  end

  def vcpu_label
    shared_vcpu? ? "Shared vCPU" : "#{cpu_shares} vCPU"
  end

  # Pricing model: monthly_price_cents is the source of truth.
  # Hourly = monthly / 720; daily = monthly / 30.
  def monthly_price_dollars
    monthly_price_cents / 100.0
  end

  def hourly_price_cents
    monthly_price_cents.to_f / HOURS_PER_MONTH
  end

  def daily_price_cents
    monthly_price_cents.to_f / 30.0
  end

  def price_per_month
    monthly_price_dollars
  end

  # True when `user` already has the maximum allowed allocations on this
  # tier (today only the free tier sets max_per_user = 1). Used by the
  # new-app form to disable the Free card when the user is already on
  # their one free app, and by the controller as a server-side guard.
  def at_cap_for?(user, exclude_app: nil)
    return false if max_per_user.blank? || user.nil?
    scope = DynoAllocation.joins(:dyno_tier, :app_record)
                          .where(dyno_tiers: { id: id })
                          .where(app_records: { created_by_id: user.id })
    scope = scope.where.not(app_record_id: exclude_app.id) if exclude_app
    scope.count >= max_per_user
  end
end
