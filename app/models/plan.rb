# OSS stub for Plan — AR-backed (User belongs_to :plan), with the
# read methods that dashboard ViewComponents call. Every quota returns
# "unlimited" (effectively a large integer) since OSS doesn't bill.

class Plan < ApplicationRecord
  KEYS = %w[free solo pro team].freeze
  SHARED_ENGINES = %w[postgres redis memcached rabbitmq meilisearch].freeze
  SHARED_ENGINES_FREE = SHARED_ENGINES

  BOX_SIZE_TO_DYNO_TIER = {
    "sleeping" => "free",
    "small"    => "basic",
    "medium"   => "standard",
    "large"    => "performance",
    "xlarge"   => "performance-2x"
  }.freeze

  DYNO_TIER_TO_BOX_SIZE = BOX_SIZE_TO_DYNO_TIER.invert.freeze

  UNLIMITED = 9_999

  # The OSS install is always treated as "free" — no billing.
  def free?  ; key == "free" || key.blank? ; end
  def solo?  ; key == "solo"  ; end
  def pro?   ; key == "pro"   ; end
  def team?  ; key == "team"  ; end

  # Quota lookups from dashboard ViewComponents (apps form, status strip,
  # template gallery). OSS has no quota so return a large number.
  def quota_for(_box_size) ; UNLIMITED ; end
  def shared_tenant_cap(_engine) ; UNLIMITED ; end
  def offers_dedicated?(_engine) ; true ; end
  def dedicated_slot_cap(_engine) ; UNLIMITED ; end
  def dedicated_size_mb(_engine) ; UNLIMITED ; end
  def shared_engines ; SHARED_ENGINES ; end
  def shared_engines_available ; SHARED_ENGINES ; end
  def allows_extras? ; true ; end

  # Seat counts referenced from workspaces/team_members. 1 seat = the
  # admin themselves; OSS has no invite quota.
  def seats_included ; UNLIMITED ; end
  def extra_seat_usd_cents ; 0 ; end
  def extra_seat_idr ; 0 ; end

  # Pricing — not displayed in OSS, but some views still ask.
  def price_usd_cents ; 0 ; end
  def price_idr ; 0 ; end

  # Retention windows used by retention prune jobs. Cap at 30 days for
  # OSS so logs/metrics don't grow forever.
  def log_retention_days ; 30 ; end
  def sample_retention_hours ; 7 * 24 ; end
  def metric_high_res_days ; 30 ; end
  def metric_aggregate_retention_days ; 90 ; end

  # Pro/Team-only features — OSS gets them all.
  def pro_features ; %w[pr_previews transfer_app scheduled_tasks] ; end
end
