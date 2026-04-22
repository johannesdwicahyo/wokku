class User < ApplicationRecord
  devise :two_factor_authenticatable, :rememberable, :validatable, :lockable,
         :timeoutable,
         :omniauthable, omniauth_providers: [ :google_oauth2, :github ],
         otp_secret_encryption_key: Rails.application.credentials.secret_key_base

  def two_factor_enabled?
    otp_required_for_login?
  end

  ADMIN_EMAIL = "admin@wokku.cloud".freeze

  enum :role, { member: 0, admin: 1 }
  enum :billing_status, { active: 0, grace_period: 1, suspended: 2 }, prefix: :billing

  validate :enforce_single_admin, if: :admin?
  validate :block_admin_email_for_members, if: -> { email == ADMIN_EMAIL && !admin? }
  validate :lock_currency_with_active_resources, if: :currency_changed?

  private def lock_currency_with_active_resources
    if resource_usages.active.billable.any?
      errors.add(:currency, "cannot be changed while you have active paid resources")
    end
  end

  # Admin sessions timeout faster (15 min vs 30 min for regular users)
  def timeout_in
    admin? ? 15.minutes : 30.minutes
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

  has_many :api_tokens, dependent: :destroy
  has_many :ssh_public_keys, dependent: :destroy
  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships
  has_many :app_records, through: :teams
  has_many :device_tokens, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :usage_events, dependent: :destroy
  has_many :resource_usages, dependent: :destroy
  has_many :deposit_transactions, dependent: :destroy

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
    subscriptions.current.includes(:plan).first&.plan || Plan.find_by(name: "free")
  end

  def balance
    currency == "idr" ? balance_idr : balance_usd_cents
  end

  def balance_formatted
    if currency == "idr"
      "Rp #{ActiveSupport::NumberHelper.number_to_delimited(balance_idr, delimiter: '.')}"
    else
      "$#{'%.2f' % (balance_usd_cents / 100.0)}"
    end
  end

  def has_payment_method?
    has_credit_card? || has_deposit_balance?
  end

  def has_credit_card?
    stripe_payment_method_id.present?
  end

  def has_deposit_balance?
    currency == "idr" ? balance_idr > 0 : balance_usd_cents > 0
  end

  def deposit_user?
    payment_method_type == "deposit"
  end

  def card_user?
    payment_method_type == "card"
  end

  def estimated_daily_cost
    hourly = resource_usages.active.billable.sum(:price_cents_per_hour)
    daily_usd_cents = hourly * 24
    if currency == "idr"
      (daily_usd_cents / 100.0 * 15_000).round
    else
      daily_usd_cents.round
    end
  end

  def days_of_balance_remaining
    daily = estimated_daily_cost
    return Float::INFINITY if daily <= 0
    (balance.to_f / daily).floor
  end

  def active_resource_usages
    resource_usages.active
  end

  def estimated_monthly_cost_cents
    now = Time.current
    period_start = now.beginning_of_month
    period_end = now.end_of_month
    resource_usages.active.billable.sum { |u| u.cost_cents_in_period(period_start, period_end) }
  end

  def free_tier_counts
    active = resource_usages.active
    {
      # Count by price (0 = free), not tier name. Tiers have been
      # renamed between "eco" and "free" and the free-tier limit
      # must not leak when names drift.
      eco_containers: active.where(resource_type: "container", price_cents_per_hour: 0).count,
      mini_databases: active.where(resource_type: "database", price_cents_per_hour: 0).count,
      starter_minio: active.where(resource_type: "database", tier_name: "starter").count
    }
  end
end
