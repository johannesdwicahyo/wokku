# Records *intent* to redeem (status: pending) and the eventual
# settlement (status: applied) once the bonus has been credited. Stays
# in the table forever as audit history — never deleted on user destroy
# of the inviter, only `applied_at` and snapshots are retained.
class PromoRedemption < ApplicationRecord
  STATUSES = %w[pending applied void].freeze

  belongs_to :promo_code
  belongs_to :redeemer_user, class_name: "User"
  # `triggered_by_deposit_id` column still exists on the table (legacy
  # audit data) but the `triggered_by_deposit` association was dropped
  # in 1.8 along with the DepositTransaction model. The promo activation
  # trigger is now an invoice payment (see Webhooks::IpaymuController +
  # Promo::ApplyBonus).

  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :applied, -> { where(status: "applied") }
end
