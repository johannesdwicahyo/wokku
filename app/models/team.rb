class Team < ApplicationRecord
  belongs_to :owner, class_name: "User"
  belongs_to :plan, optional: true # PR A: nullable; PR B flips this to required
  has_many :team_memberships, dependent: :destroy
  has_many :users, through: :team_memberships
  has_many :servers, dependent: :destroy
  has_many :app_records, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :cloud_credentials, dependent: :destroy

  # Personal vs org distinction (PR A: nullable for backfill window).
  # Personal teams ship with every user signup; org teams are
  # explicitly created by the user and require a paid plan.
  enum :kind, { personal: 0, org: 1 }, prefix: true

  validates :name, presence: true, uniqueness: true
  validates :slug, uniqueness: { case_sensitive: false }, allow_nil: true,
                    format: { with: /\A[a-z0-9][a-z0-9-]*\z/, message: "must be lowercase alphanumeric with hyphens" }

  # One personal team per owner (dedupe invariant). Org teams are unlimited.
  validates :owner_id, uniqueness: { scope: :kind }, if: :personal?

  # Phase 4 billing defaults. Every new team starts the 7-day free trial
  # clock and gets a billing anchor on its create date — without these,
  # `next_billing_date` returns nil and any Free→Paid upgrade crashes on
  # `nil.prev_month` inside Billing::PlanChange#issue_proration_invoice.
  before_validation :assign_billing_anchor_and_trial, on: :create

  def assign_billing_anchor_and_trial
    self.billing_anchor_date ||= Date.current
    self.trial_ends_at ||= 7.days.from_now
  end

  def personal?
    kind == "personal"
  end

  def org?
    kind == "org"
  end

  # ---------------------------------------------------------------------
  # PR B billing API — Team is now the canonical billing parent. Mirrors
  # the helpers that lived on User pre-refactor. User#... shims delegate
  # to personal_team during the deprecation window.
  # ---------------------------------------------------------------------

  # The team's plan, falling back to Plan(free). The managed cloud
  # PREPENDS an active-subscription override on top of this (see
  # config/initializers/wokku_cloud_billing.rb) — the engine itself
  # never names Subscription.
  def current_plan
    plan || Plan.find_by(key: "free")
  end

  def on_trial?
    trial_ends_at.present? && trial_ends_at > Time.current
  end

  # Next month-boundary aligned to billing_anchor_date.day. If the anchor
  # day is the 31st and the next month has fewer days, snap to last day.
  # Returns nil for teams that never started billing (Free + never paid).
  def next_billing_date
    return nil if billing_anchor_date.nil?
    base = Date.current >= billing_anchor_date ? Date.current : billing_anchor_date
    candidate = Date.new(base.year, base.month, [ billing_anchor_date.day, Date.new(base.year, base.month, -1).day ].min)
    candidate <= Date.current ? candidate.next_month : candidate
  end
end
