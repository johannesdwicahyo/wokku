module PlanEnforceable
  extend ActiveSupport::Concern

  # Box sizes ordered smallest → largest. `sleeping` is the floor; a
  # deploy is never auto-upgraded *into* sleeping.
  BOX_SIZE_ORDER = %w[sleeping small medium large xlarge].freeze

  class PlanQuotaError < StandardError
    attr_reader :size, :allowed, :requested
    def initialize(size:, allowed:, requested:)
      @size, @allowed, @requested = size, allowed, requested
      super("Plan allows #{allowed} #{size} boxes, attempted #{requested}.")
    end
  end

  # Per-resource billing: a paid size over the account's resource limit
  # (the new-account cap). Subclass so every existing rescue still catches it.
  class AccountLimitError < PlanQuotaError
    MESSAGE = "That size is over your account limit — add credit on the Billing page to go higher.".freeze
    def message = MESSAGE
  end

  # ---------------------------------------------------------------------------
  # Box-quota enforcement (public — called from controllers + specs)
  # Renamed from slot_count → box_count in the 1.9 box-rename.
  # ---------------------------------------------------------------------------

  def current_box_count(user, size)
    user.teams.flat_map(&:app_records).flat_map(&:dyno_allocations).select do |a|
      a.dyno_tier&.size_key == size.to_s
    end.sum(&:count)
  end

  # Smallest box size >= `required` that the user's plan grants with free
  # headroom. Lets a Team (large-only) user deploy a small-min template on
  # a large box instead of being blocked. Falls back to the exact required
  # size when nothing fits, so the existing `enforce_plan_quota!` limit
  # error still fires.
  def resolve_box_size(user, required:)
    req = required.to_s
    idx = BOX_SIZE_ORDER.index(req)
    return req if idx.nil?

    BOX_SIZE_ORDER[idx..].find { |size|
      within_plan_quota?(user, size: size, additional: 1)
    } || req
  end

  # Total boxes of `size` the user may run. Plan + box-addon math lives in
  # the injected enforcer (managed: Billing::PlanEnforcer; OSS: unlimited).
  def quota_allowed(user, size)
    Wokku.config.plan_enforcer.quota(user, :box, size)
  end

  def within_plan_quota?(user, size:, additional:)
    allowed = quota_allowed(user, size)
    used    = current_box_count(user, size)
    (used + additional) <= allowed
  end

  def enforce_plan_quota!(user, size:, additional:)
    # Per-resource billing retired the plans' paid box quotas: paid sizes
    # are gated by the account limit instead. Sleeping keeps its quota.
    return enforce_account_limit!(user, size: size, additional: additional) if Wokku.config.resource_builder? && size.to_s != "sleeping"

    allowed = quota_allowed(user, size)
    used    = current_box_count(user, size)
    if (used + additional) > allowed
      raise PlanQuotaError.new(size: size, allowed: allowed, requested: used + additional)
    end
  end

  # Per-size snapshot for the new-app box picker — the single source of
  # truth the UI shares with enforce_plan_quota!, so the form never offers
  # a size that `create` would reject (the bug this fixes).
  #
  # `provisionable` honors resolve_box_size's auto-upgrade: a size with no
  # headroom of its own is still provisionable when a *larger* granted size
  # has room, because the create request gets upgraded into it. Equivalent
  # to `within_plan_quota?(resolve_box_size(...))` but computed from a
  # single usage walk so it's cheap enough for the apps index instant shell.
  # Display cap for the unlimited (OSS null-enforcer) case: the picker
  # snapshot feeds `.to_i` view math, and Float::INFINITY.to_i raises
  # FloatDomainError. Managed quotas are tiny, so the clamp never binds.
  UNLIMITED_DISPLAY_CAP = 1_000_000

  def box_picker_state(user)
    used    = box_usage_by_size(user)
    allowed = BOX_SIZE_ORDER.index_with { |size| [ quota_allowed(user, size), UNLIMITED_DISPLAY_CAP ].min }

    BOX_SIZE_ORDER.each_with_index.each_with_object({}) do |(size, idx), state|
      free = ->(s) { allowed[s] - used.fetch(s, 0) }
      state[size] = {
        allowed: allowed[size],
        used: used.fetch(size, 0),
        remaining: [ free.call(size), 0 ].max,
        # mirrors resolve_box_size: any granted size >= this one with room
        provisionable: BOX_SIZE_ORDER[idx..].any? { |s| free.call(s) >= 1 }
      }
    end
  end

  private

  # One pass over the user's dyno allocations → { size_key => total count }.
  # Backs both box_picker_state and (conceptually) current_box_count.
  def box_usage_by_size(user)
    user.teams.flat_map(&:app_records).flat_map(&:dyno_allocations).each_with_object(Hash.new(0)) do |alloc, acc|
      key = alloc.dyno_tier&.size_key
      acc[key] += alloc.count if key
    end
  end

  # ---------------------------------------------------------------------------
  # Deposit / billing enforcement
  # ---------------------------------------------------------------------------

  # Scale-up gate. For paid tiers, verify the deposit can cover the
  # NEW daily rate (existing usage + whatever the new tier costs).
  # Free tiers pass through.
  def enforce_payment_method!(tier_price_cents_per_hour)
    return if tier_price_cents_per_hour == 0
    enforce_deposit_covers_one_day!(additional_hourly_cost_cents_usd: tier_price_cents_per_hour)
  end

  # Deposit gate: allow creation if the user's balance covers at least
  # one more day at current (or projected) hourly spend.
  #
  #   additional_hourly_cost_cents_usd: pass the incoming resource's
  #     price (USD cents/hour). Defaults to 0 since apps start at the
  #     Free tier — scale-up to a paid tier is gated separately.
  #
  # Applies uniformly: the IDR launch model is prepaid-deposit only.
  # Credit cards are just a funding source for deposit top-ups, not a
  # separate invoicing path, so CC users hit the same deposit check.
  # Free/zero-cost resources still pass trivially when current usage
  # is also zero.
  def enforce_deposit_covers_one_day!(additional_hourly_cost_cents_usd: 0)
    # Money/balance math lives in the enforcer so this concern never
    # resolves Billing:: (absent in OSS; the null enforcer returns nil).
    shortfall = Wokku.config.plan_enforcer.deposit_shortfall(
      current_user, additional_hourly_cost_cents_usd: additional_hourly_cost_cents_usd
    )
    return if shortfall.nil?

    alert_msg = "Deposit doesn't cover 1 day of usage at this level. Top up to continue."
    # ActionController::API (used by /api/v1/*) doesn't include
    # respond_to, so branch on request format manually.
    if request.format.json? || request.path.start_with?("/api/")
      render json: {
        error: alert_msg,
        url: "/dashboard/billing",
        current_balance: shortfall[:balance],
        required_one_day: shortfall[:required]
      }, status: :payment_required
    else
      redirect_to dashboard_billing_path, alert: alert_msg
    end
  end

  # Back-compat aliases — the semantic is now a deposit check regardless
  # of whether the new resource is a container or database.
  def enforce_free_container_limit!
    enforce_deposit_covers_one_day!
  end

  def enforce_free_database_limit!(service_type = nil)
    enforce_deposit_covers_one_day!
  end

  def track_resource_created(resource_type:, resource_id_ref:, tier_name:, price_cents_per_hour:, metadata: {})
    current_user.resource_usages.create!(
      resource_type: resource_type,
      resource_id_ref: resource_id_ref,
      tier_name: tier_name,
      price_cents_per_hour: price_cents_per_hour,
      started_at: Time.current,
      metadata: metadata
    )
  end

  def track_resource_destroyed(resource_type:, resource_id_ref:)
    current_user.resource_usages
      .active
      .where(resource_type: resource_type, resource_id_ref: resource_id_ref)
      .find_each(&:stop!)
  end

  private

  def enforce_account_limit!(user, size:, additional:)
    team = user.teams.first
    tier = DynoTier.find_by(name: DynoTier::BOX_SIZE_TO_DYNO_TIER[size.to_s])
    shape = Resources::ApplyChange.shape_for_dyno_tier(tier)
    return unless team && shape

    before = Resources::ApplyChange.team_allocations(team)
    after = before + [ { shape: shape, instances: additional } ]
    return if Wokku.config.plan_enforcer.allowed?(team, :resources, from: before, to: after)

    raise AccountLimitError.new(size: size, allowed: 0, requested: additional)
  end
end
