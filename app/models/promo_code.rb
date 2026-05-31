# Single model for all three promo phases (manual / channel / referral).
# What differs is configuration, not behaviour:
#
#   manual_credit  — admin-issued, instant grant, no deposit required.
#   channel_match  — public code per channel, redeemer-only bonus on first
#                    qualifying deposit.
#   referral       — auto-generated per user, two-sided bonus on the
#                    referee's first qualifying deposit.
#
# Bonuses are denominated in IDR cents-equivalent (whole rupiah). USD
# customers don't see promo flow today; if they ever do, mirror with
# `redeemer_bonus_usd_cents` rather than rate-converting on the fly.
class PromoCode < ApplicationRecord
  KINDS = %w[manual_credit channel_match referral].freeze

  belongs_to :inviter_user, class_name: "User", optional: true
  belongs_to :created_by,   class_name: "User", optional: true
  has_many   :promo_redemptions, dependent: :destroy

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :kind, inclusion: { in: KINDS }
  validates :redeemer_bonus_idr, :inviter_bonus_idr, :redemptions_count,
            numericality: { greater_than_or_equal_to: 0 }

  before_validation :normalise_code

  scope :active, -> { where(active: true).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def redeemable?
    return false unless active?
    return false if expires_at && expires_at <= Time.current
    return true  if max_redemptions.nil?
    redemptions_count < max_redemptions
  end

  def referral?
    kind == "referral"
  end

  # Manual-credit codes always pay out on redemption (no min-spend gate).
  # Previously gated by `min_deposit_idr` which was dropped in 1.8.
  def instant_grant?
    kind == "manual_credit"
  end

  private

  def normalise_code
    self.code = code.to_s.strip.upcase if code.present?
  end
end
