class User < ApplicationRecord
  devise :two_factor_authenticatable, :rememberable, :validatable, :lockable,
         :timeoutable,
         :omniauthable, omniauth_providers: [ :google_oauth2, :github, :gitlab, :bitbucket, :apple ],
         otp_secret_encryption_key: Rails.application.credentials.secret_key_base

  encrypts :gitlab_access_token, :gitlab_refresh_token,
           :bitbucket_access_token, :bitbucket_refresh_token,
           :apple_refresh_token

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

  # Env-overridable so a self-host names its own admin; managed keeps the
  # default. The single-admin validation keys off this.
  # Downcased: OAuth emails are compared downcased, and Devise stores
  # emails downcased — an operator setting WOKKU_ADMIN_EMAIL with any
  # uppercase must still match the admin branch and the seeded row.
  ADMIN_EMAIL = ENV.fetch("WOKKU_ADMIN_EMAIL", "admin@wokku.cloud").downcase.freeze

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
      # Only teams the user OWNS — apps of teams they merely belong to keep running.
      owned_teams.flat_map(&:app_records).each do |app|
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

  # Sliding session timeout. Devise resets the clock on every authenticated
  # request, so an active user effectively stays logged in. Admins still
  # get a tighter window because their actions are higher-stakes.
  def timeout_in
    admin? ? 1.day : 30.days
  end

  # Engine rule: exactly one admin. The cloud additionally PINS the admin
  # to its reserved address (config/initializers/wokku_cloud_admin.rb) —
  # a self-host's first-boot /setup picks any email.
  private def enforce_single_admin
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
  # Any email change (profile page, admin, console) drops provider-verified
  # status unless the same save sets the flag explicitly.
  before_update { self.email_provider_verified = false if will_save_change_to_email? && !will_save_change_to_email_provider_verified? }

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

  # Idempotently ensure the user has a personal team (created on first
  # signup). Returns [team, created?] so callers can gate first-time-signup
  # side effects. teams.name carries a UNIQUE index, so the derived
  # "<name>'s Team" can collide across users; we disambiguate instead of
  # letting Team.create! raise RecordInvalid — that surfaced as a 422 on
  # the OAuth callback for new users whose name matched an existing team.
  def ensure_personal_team!
    if (existing = personal_team)
      return [ existing, false ]
    end

    base = "#{name.presence || email.to_s.split('@').first}'s Team"
    team = nil
    10.times do |i|
      candidate = i.zero? ? base : "#{base} #{i + 1}"
      team = Team.new(kind: :personal, owner: self, name: candidate)
      begin
        break if team.save
      rescue ActiveRecord::RecordNotUnique
        team = nil # lost a race on the unique index; try the next candidate
      end
    end
    raise ActiveRecord::RecordInvalid, (team || Team.new(owner: self)) unless team&.persisted?

    TeamMembership.create!(user: self, team: team, role: :admin)
    [ team, true ]
  end

  has_many :device_tokens, dependent: :destroy
  has_many :mobile_auth_codes, dependent: :delete_all
  has_many :alert_mutes, dependent: nil
  has_many :known_devices, dependent: :destroy

  def self.from_omniauth(auth)
    email = auth.info.email&.downcase

    # Admin email: link OAuth to existing seed account, never create a new one
    if email == ADMIN_EMAIL
      admin = find_by(email: ADMIN_EMAIL, role: :admin)
      unless admin
        Rails.logger.warn("OAuth attempt for admin email but no seed account exists")
        return new # unpersisted — triggers failure redirect
      end
      # Link OAuth provider on first sign-in so future logins find by
      # provider+uid — but ONLY on a verified email, else a provider that
      # lets a caller assert an arbitrary unverified admin@ email would
      # take over the highest-value account (same gate as the user path).
      if admin.provider.blank?
        return new unless oauth_email_verified?(auth)
        admin.update_columns(provider: auth.provider, uid: auth.uid, avatar_url: auth.info.image, name: auth.info.name)
      end
      return admin
    end

    # Closed-registration installs (self-host default): only existing
    # accounts may OAuth in. Match on provider+uid first; fall back to
    # email ONLY when the provider asserts it's verified and the target
    # account isn't already linked — otherwise an attacker whose OAuth
    # account carries an unverified victim@ email could take the account
    # over. Never re-link an account that already has a provider/uid.
    unless Wokku.config.open_registration
      existing = find_by(provider: auth.provider, uid: auth.uid)
      if existing.nil? && email.present? && oauth_email_verified?(auth)
        candidate = find_by(email: email)
        existing = candidate if candidate&.provider.blank?
      end
      if existing
        existing.update_columns(provider: auth.provider, uid: auth.uid, email_provider_verified: true) if existing.provider.blank?
        return existing
      end
      return new # unpersisted — triggers the failure redirect
    end

    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email = email
      user.email_provider_verified = true
      user.password = Devise.friendly_token[0, 20]
      user.name = auth.info.name
      user.avatar_url = auth.info.image
      user.github_username = auth.info.nickname if auth.provider == "github"
    end
  end

  # Whether the OAuth response carries a *verified* email — the gate for
  # linking to a pre-existing account by email. OIDC/Google expose an
  # explicit claim; GitHub/GitLab/Bitbucket only ever return the account's
  # own primary email, which those providers require to be verified, so a
  # present primary email is trustworthy. Anything else → treat unverified.
  def self.oauth_email_verified?(auth)
    raw = auth.extra&.raw_info || {}
    flag = raw["email_verified"]
    flag = raw[:email_verified] if flag.nil?
    return ActiveModel::Type::Boolean.new.cast(flag) unless flag.nil?

    %w[github gitlab bitbucket].include?(auth.provider.to_s)
  end

  # Sign in with Apple (web callback and POST /api/v1/auth/apple share this).
  # apple_uid is its own column, so linking never overwrites a GitHub/Google
  # provider/uid. Verified email links to an existing account (founder
  # decision 2026-10-24); relay addresses match nothing and create one.
  def self.from_apple(claims, name: nil)
    sub = claims["sub"].to_s
    return new if sub.blank?

    if (user = find_by(apple_uid: sub))
      return user
    end

    email = claims["email"].to_s.downcase.presence
    return new unless email
    verified = ActiveModel::Type::Boolean.new.cast(claims["email_verified"]) == true

    if email == ADMIN_EMAIL
      admin = find_by(email: ADMIN_EMAIL, role: :admin)
      return new unless admin && verified && admin.apple_uid.blank?
      admin.update_columns(apple_uid: sub)
      return admin
    end

    if verified && (existing = find_by(email: email))
      # Only link when the stored email came from a provider; a self-edited
      # email could be an attacker's pre-hijack of the victim's address.
      return new unless existing.email_provider_verified
      return new if existing.apple_uid.present? # already linked to another Apple ID
      existing.update_columns(apple_uid: sub)
      return existing
    end

    return new unless Wokku.config.open_registration

    create(email: email, password: Devise.friendly_token[0, 20], name: name.presence,
           apple_uid: sub, provider: "apple", uid: sub, email_provider_verified: true)
  end

  # The refresh token is kept only so it can be revoked at hard delete.
  def remember_apple_refresh_token!(token, client_id:)
    return if token.blank?
    assign_attributes(apple_refresh_token: token, apple_token_client_id: client_id)
    save!(validate: false)
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

  def card_user?
    payment_method_type == "card"
  end

  # Phase 4 invoice-based billing helpers ----------------------------------


  def on_trial?
    !!personal_team&.on_trial?
  end

  def next_billing_date
    personal_team&.next_billing_date
  end
end
