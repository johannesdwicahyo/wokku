# Records *intent* to redeem (status: pending) and the eventual
# settlement (status: applied) once the bonus has been credited. Stays
# in the table forever as audit history — never deleted on user destroy
# of the inviter, only `applied_at` and snapshots are retained.
class PromoRedemption < ApplicationRecord
  STATUSES = %w[pending applied void].freeze

  belongs_to :promo_code
  belongs_to :redeemer_user,         class_name: "User"
  belongs_to :triggered_by_deposit,  class_name: "DepositTransaction", optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :applied, -> { where(status: "applied") }
end
