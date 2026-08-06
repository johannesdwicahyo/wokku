# A pending request from one user to transfer ownership of an AppRecord
# to another. Until the target accepts, the source still owns the app and
# is still being billed for it. Accept rotates billing segments under the
# new owner and moves the AppRecord to the target's personal team.
class AppTransfer < ApplicationRecord
  EXPIRY = 7.days

  belongs_to :app_record
  belongs_to :from_user, class_name: "User"
  belongs_to :to_user,   class_name: "User"

  STATUSES = %w[pending accepted declined cancelled expired].freeze
  validates :status, inclusion: { in: STATUSES }

  scope :pending,   -> { where(status: "pending") }
  scope :for_inbox, ->(user) { where(to_user: user, status: "pending").where("expires_at > ?", Time.current) }

  before_validation :set_default_expiry, on: :create

  def pending?
    status == "pending" && expires_at > Time.current
  end

  def expired?
    status == "expired" || (status == "pending" && expires_at <= Time.current)
  end

  private

  def set_default_expiry
    self.expires_at ||= EXPIRY.from_now
    self.status     ||= "pending"
  end
end
