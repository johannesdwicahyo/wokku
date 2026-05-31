class User < ApplicationRecord
  devise :two_factor_authenticatable, :rememberable, :validatable, :lockable,
         :timeoutable,
         :omniauthable, omniauth_providers: [ :google_oauth2, :github, :gitlab, :bitbucket ],
         otp_secret_encryption_key: Rails.application.credentials.secret_key_base

  encrypts :gitlab_access_token, :gitlab_refresh_token,
           :bitbucket_access_token, :bitbucket_refresh_token

  def two_factor_enabled?
    otp_required_for_login?
  end

  TOKEN_REFRESH_WINDOW = 60.seconds

  def gitlab_token_expired?
    return true if gitlab_access_token.blank?
    gitlab_token_expires_at.nil? || gitlab_token_expires_at <= Time.current + TOKEN_REFRESH_WINDOW
  end

  def bitbucket_token_expired?
    return true if bitbucket_access_token.blank?
    bitbucket_token_expires_at.nil? || bitbucket_token_expires_at <= Time.current + TOKEN_REFRESH_WINDOW
  end

  ADMIN_EMAIL = "admin@wokku.cloud".freeze

  enum :role, { member: 0, admin: 1 }
  enum :billing_status, { active: 0, grace_period: 1, suspended: 2 }, prefix: :billing

  enum :onboarding_status, { pending: 0, active: 1, completed: 2, skipped: 3 },
       prefix: :onboarding

  # Tour lifecycle helpers (see docs/.../first-app-guided-tour-design.md)
  def tour_active?
    onboarding_active?
  end

  def tour_finished?
    onboarding_completed? || onboarding_skipped?
  end

  def activate_tour!
    return unless onboarding_pending?
    update!(onboarding_status: :active, onboarding_step: 0)
  end

  def advance_tour_to(step)
    return unless tour_active?
    update!(onboarding_step: step) if step > onboarding_step
  end

  def complete_tour!
    update!(onboarding_status: :completed) unless tour_finished?
  end

  def skip_tour!
    update!(onboarding_status: :skipped) unless tour_finished?
  end

  GRACE_PERIOD = 3.days

  scope :active,            -> { where(deleted_at: nil) }
  scope :pending_deletion,  -> { where.not(deletion_scheduled_at: nil).where(deleted_at: nil) }
  scope :ready_for_hard_delete, -> { pending_deletion.where("deletion_scheduled_at <= ?", Time.current) }

  def deleted?
    deleted_at.present?
  end

  def deletion_pending?
    deletion_scheduled_at.present? && !deleted?
  end

  def schedule_deletion!
    return if deletion_pending? || deleted?

    transaction do
      update!(deletion_scheduled_at: GRACE_PERIOD.from_now)
      teams.flat_map(&:app_records).each do |app|
        DokkuAppActionJob.perform_later(app.id, "stop")
      rescue => e
        Rails.logger.warn("schedule_deletion!: failed to enqueue stop for app #{app.id}: #{e.message}")
      end
    end
  end

  def cancel_deletion!
    update!(deletion_scheduled_at: nil)
  end

  def admin_hard_delete!(by:)
    HardDeleteAccountJob.perform_later(id, admin_email: by.email)
  end

  # Prevent hard-deleted accounts from signing in. Soft-deleted users
  # (pending grace period) can still log in to cancel or contact support.
  def active_for_authentication?
    super && !deleted?
  end

  def inactive_message
    deleted? ? :account_deleted : super
  end

  validate :enforce_single_admin, if: :admin?
  validate :block_admin_email_for_members, if: -> { email == ADMIN_EMAIL && !admin? }
  validate :lock_currency_with_active_resources, if: :currency_changed?
  before_validation :default_currency_for_launch_mode, on: :create
  before_validation :default_payment_method_for_launch_mode, on: :create

  private def assign_default_plan
    self.plan ||= Plan.find_by(key: "free")
  end

  private def default_currency_for_launch_mode
    # While we're IDR-only (Indonesia launch), override the schema
    # default of "usd" so every new signup lands in the IDR/iPaymu flow.
    self.currency = "idr" if Wokku::LaunchMode.idr_only? && (currency.blank? || currency == "usd")
  end

  private def default_payment_method_for_launch_mode
    # Under IDR-only launch every new user is implicitly a deposit user
    # (only payment path is iPaymu top-up). The schema default of "none"
    # excluded them from BalanceChecker, letting balances drift negative
    # without warnings or suspension. Make them deposit users at signup
    # so balance/billing safeguards apply from day one.
    return unless Wokku::LaunchMode.idr_only?
    self.payment_method_type = "deposit" if payment_method_type.blank? || payment_method_type == "none"
  end

  private def lock_currency_with_active_resources
    # Phase 4: paid resources are billed via Invoice now, not ResourceUsage.
    # Lock currency while the user has any unpaid invoice — switching
    # currency mid-cycle would split their books.
    if invoices.unpaid.any?
      errors.add(:currency, "cannot be changed while you have unpaid invoices")
    end
  end

  # Sliding session timeout. Devise resets the clock on every authenticated
  # request, so an active user effectively stays logged in. Admins still
  # get a tighter window because their actions are higher-stakes.
  def timeout_in
    admin? ? 1.day : 30.days
  end

  private def enforce_single_admin
    unless email == ADMIN_EMAIL
      errors.add(:role, "admin role is restricted to #{ADMIN_EMAIL}")
    end
    if User.where(role: :admin).where.not(id: id).exists?
      errors.add(:role, "only one admin account is allowed")
    end
  end

  # Prevent anyone from creating a member account with the admin email
  private def block_admin_email_for_members
    errors.add(:email, "is reserved")
  end

  belongs_to :plan
  belongs_to :pending_plan, class_name: "Plan", optional: true

  before_validation :assign_default_plan, on: :create

  has_many :api_tokens, dependent: :destroy
  has_many :ssh_public_keys, dependent: :destroy
  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships
  has_many :app_records, through: :teams
  # Strict-delegate cleanup: User#destroy must take owned teams with it
  # so the NOT NULL owner_id FK doesn't violate.
  has_many :owned_teams, class_name: "Team", foreign_key: :owner_id, dependent: :destroy

  # PR A of personal+multi-team refactor: stable lookup for the
  # user's personal workspace. After backfill every existing user has
  # exactly one team kind: :personal. PR B will resolve current_team
  # from session and fall back here.
  def personal_team
    teams.where(kind: "personal").order(:created_at).first || teams.order(:created_at).first
  end
  has_many :device_tokens, dependent: :destroy
  has_many :known_devices, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :invoice_credits, dependent: :destroy
  has_many :usage_events, dependent: :destroy
  has_many :promo_redemptions, foreign_key: :redeemer_user_id, dependent: :destroy
  has_many :invited_promo_codes, class_name: "PromoCode", foreign_key: :inviter_user_id, dependent: :destroy
  has_one  :referral_promo_code, -> { where(kind: "referral") }, class_name: "PromoCode", foreign_key: :inviter_user_id

  after_create :ensure_referral_promo_code

  # Phase 3 referral: every user gets a personal code at signup. Idempotent
  # so the after_create can be re-run for backfill on existing users.
  def ensure_referral_promo_code!
    return referral_promo_code if referral_promo_code

    code = nil
    20.times do
      candidate = "REF-#{SecureRandom.alphanumeric(6).upcase}"
      next if PromoCode.exists?(code: candidate)
      code = candidate
      break
    end
    raise "could not generate unique referral code" unless code

    PromoCode.create!(
      code: code,
      kind: "referral",
      redeemer_bonus_idr: 10_000,
      inviter_bonus_idr: 10_000,
      inviter_user: self,
      description: "Auto-generated referral code"
    )
  end

  private def ensure_referral_promo_code
    ensure_referral_promo_code!
  rescue StandardError => e
    # Don't break signup if code generation hits a uniqueness collision —
    # ProfileController exposes a "regenerate referral code" affordance,
    # and the after_create can be retried.
    Rails.logger.warn("ensure_referral_promo_code failed for user #{id}: #{e.message}")
  end

  def self.from_omniauth(auth)
    email = auth.info.email&.downcase

    # Admin email: link OAuth to existing seed account, never create a new one
    if email == ADMIN_EMAIL
      admin = find_by(email: ADMIN_EMAIL, role: :admin)
      unless admin
        Rails.logger.warn("OAuth attempt for admin email but no seed account exists")
        return new # unpersisted — triggers failure redirect
      end
      # Link OAuth provider on first sign-in so future logins find by provider+uid
      if admin.provider.blank?
        admin.update_columns(provider: auth.provider, uid: auth.uid, avatar_url: auth.info.image, name: auth.info.name)
      end
      return admin
    end

    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email = email
      user.password = Devise.friendly_token[0, 20]
      user.name = auth.info.name
      user.avatar_url = auth.info.image
      user.github_username = auth.info.nickname if auth.provider == "github"
    end
  end

  def current_plan
    # Strict delegate — Team is the canonical billing parent.
    # Plan(free) only when there's truly no team yet (mid-signup).
    personal_team&.current_plan || Plan.find_by(key: "free")
  end

  # Display-layer currency resolution. In IDR-only launch mode, every
  # UI path renders IDR regardless of what the user's row holds.
  def effective_currency
    Wokku::LaunchMode.idr_only? ? "idr" : currency
  end

  # 1.8: shim layer — `balance`, `balance_formatted`, `has_deposit_balance?`,
  # `days_of_balance_remaining`, `deposit_user?`, `estimated_monthly_cost_cents`
  # all referenced legacy columns/models that are gone. The views still call
  # them in a few places; rather than rewrite the dashboard right now (that
  # work lives in backlog 0.12 — brutalist refactor + dashboard rewrite),
  # return safe zero/empty values so the views render without crashing.
  def balance                       = 0
  def balance_formatted             = "Rp 0"
  def has_deposit_balance?          = false
  def days_of_balance_remaining     = Float::INFINITY
  def deposit_user?                 = payment_method_type == "deposit"
  def estimated_daily_cost          = 0
  def estimated_monthly_cost_cents  = 0
  def active_resource_usages        = []
  def free_tier_counts              = { eco_containers: 0, mini_databases: 0, starter_minio: 0 }

  # Phase 4: payment method is now driven by plan + invoice flow.
  # Trial users + paid-plan users with a current paid invoice are "paid".
  def has_payment_method?
    invoices.paid.exists? || on_trial?
  end

  def card_user?
    payment_method_type == "card"
  end

  # Phase 4 invoice-based billing helpers ----------------------------------

  has_many :invoices, dependent: :destroy

  def on_trial?
    !!personal_team&.on_trial?
  end

  def next_billing_date
    personal_team&.next_billing_date
  end
end
