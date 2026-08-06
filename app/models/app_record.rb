class AppRecord < ApplicationRecord
  # Webhook secrets are HMAC-SHA256 shared secrets — a leak lets an attacker
  # forge push / pull_request events and trigger deploys. Encrypt at rest.
  # Non-deterministic: we never look up rows by these values, only compare
  # HMAC signatures after decryption.
  encrypts :git_webhook_secret, :github_webhook_secret

  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  # CLI/API consumers pass either an app's UUID or its human name.
  # Names are what users actually type (heroku/fly/railway pattern); the
  # UUID path stays for API integrations and dashboard URLs.
  def self.lookup!(id_or_name)
    if id_or_name.to_s.match?(UUID_PATTERN)
      find(id_or_name)
    else
      find_by!(name: id_or_name)
    end
  end

  # B6 W2: standard creates birth apps wokkud-native (no dokku shell, all
  # wokkud flags on). Flipped 2026-07-19 after the §4 creation smoke passed
  # on prod (w2-smoke: no dokku app ever, EnvVar-only env, wokkud build →
  # converge → serving). Templates/previews still provision dokku-side —
  # they never set wokkud_native
  # (docs/superpowers/specs/2026-07-19-b6-w2-wokkud-native-provisioning.md).
  def self.native_creates? = true

  # B6 W3: EnvVar rows are the runtime-env truth for EVERY app. Flipped
  # 2026-07-19 after `envs:import_all` mirrored all 28 non-native apps with
  # per-app parity verified. Writers keep mirroring to dokku for non-native
  # apps as the revert path until B6 deletes dokku; out-of-band dokku-side
  # config:set is IGNORED from here on — that's the point of ownership.
  def self.cp_env_truth? = true

  # Runtime env for this app. EnvVar rows ARE the truth for every app
  # (W3 flip; dokku fallback deleted in W7 Phase 1).
  def runtime_env
    env_vars.pluck(:key, :value).to_h
  end

  belongs_to :server
  belongs_to :team
  belongs_to :creator, class_name: "User", foreign_key: :created_by_id

  # Resolves the plan whose retention/quota rules apply to this app.
  # Falls back to Plan(free) if the app has no owner or its owner has no
  # current subscription. Cached per instance — the per-plan retention
  # jobs call this once per app per pass and don't tolerate N+1 hits.
  def owner_plan
    @owner_plan ||= creator&.current_plan || Plan.find_by(key: "free")
  end
  belongs_to :parent_app, class_name: "AppRecord", optional: true
  has_many :preview_apps, class_name: "AppRecord", foreign_key: :parent_app_id, dependent: :destroy

  has_many :releases, dependent: :destroy
  has_many :deploys, dependent: :destroy
  has_many :domains, dependent: :destroy
  has_many :logs, dependent: :destroy
  has_many :request_samples, dependent: :destroy
  has_many :request_aggregates, dependent: :destroy
  has_many :metric_hourly, dependent: :destroy
  has_many :env_vars, dependent: :destroy
  has_many :process_scales, dependent: :destroy
  has_many :app_databases, dependent: :destroy
  has_many :database_services, through: :app_databases
  has_many :volume_backups, -> { kind_volume }, class_name: "Backup", dependent: :destroy

  # The "primary" database for app-scoped flows (backup-now, overview
  # card, etc). In steady state every app has at most one DB attached
  # (enforced post-Phase-3 #17); for legacy multi-DB apps we pick the
  # oldest attachment so behavior is deterministic.
  def primary_database
    database_services.order(:created_at).first
  end

  # Most recent backup across attached databases. Returns nil if no
  # database is attached or if no backups exist yet.
  def last_backup
    db = primary_database
    return nil if db.nil?
    db.backups.order(created_at: :desc).first
  end
  has_many :metrics, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :dyno_allocations, dependent: :destroy
  has_many :scheduled_tasks, dependent: :destroy
  has_many :vitals_events,         dependent: :delete_all
  has_many :vitals_hourly_rollups, dependent: :delete_all
  has_many :crash_events,          dependent: :destroy
  has_many :incidents,             dependent: :destroy
  has_many :lifecycle_ops,         dependent: :destroy
  has_one :preview_dns_record, dependent: :destroy

  def ensure_vitals_ingest_token!
    return vitals_ingest_token if vitals_ingest_token.present?
    update!(vitals_ingest_token: SecureRandom.urlsafe_base64(24))
    vitals_ingest_token
  end

  def rotate_vitals_ingest_token!
    update!(vitals_ingest_token: SecureRandom.urlsafe_base64(24))
    vitals_ingest_token
  end

  # DynoAllocation's `after_destroy :close_usage_segment` only closes
  # The ResourceUsage segment cleanup on destroy was dropped in 1.8
  # along with the segment model itself.

  enum :status, { running: 0, stopped: 1, crashed: 2, deploying: 3, sleeping: 4, created: 5 }

  # Bundle v2 — user-facing box size, picked at creation from the plan's
  # box_quotas. Backfilled from dyno_allocations.web.dyno_tier.name via
  # AddBoxSizeAndEnabledSharedEnginesToAppRecords. Stays in sync with
  # dyno_tier going forward via PlanEnforceable (TBD in Phase 7 sweep).
  BOX_SIZES = %w[sleeping small medium large xlarge].freeze
  validates :box_size, inclusion: { in: BOX_SIZES }, allow_nil: true

  # Bundle v2 — which of the 5 shared engines the box has attached.
  # User-pick per box at creation; editable from box settings; cascade-
  # destroyed with the box (handled by Addons::SharedProvisioner cleanup
  # in Phase 7 sweep). Default empty array.
  SHARED_ENGINES = DatabaseService::SHARED_ENGINES
  validate :enabled_shared_engines_subset_of_known

  def shared_engine_enabled?(engine)
    enabled_shared_engines.include?(engine.to_s)
  end

  private

  def enabled_shared_engines_subset_of_known
    extras = Array(enabled_shared_engines).map(&:to_s) - SHARED_ENGINES
    errors.add(:enabled_shared_engines, "unknown engine(s): #{extras.join(', ')}") if extras.any?
  end

  public

  # Live-update the action button area on the show page when an
  # async action (restart/stop/start) starts or finishes. The button
  # frame is rendered server-side and replaced via Turbo Stream from
  # this hook so users see "Restarting…" disabled until the job
  # completes — see DokkuAppActionJob.
  after_update_commit :broadcast_actions_frame, if: :saved_change_to_pending_action?

  def broadcast_actions_frame
    broadcast_replace_to action_stream_name,
      target: ActionView::RecordIdentifier.dom_id(self, :actions),
      partial: "dashboard/apps/actions",
      locals: { app: self }
  end

  # Append a toast notification to subscribed pages. Used by the action
  # job to surface success/failure when the SSH call completes.
  def broadcast_action_toast(level:, message:)
    Turbo::StreamsChannel.broadcast_append_to(
      action_stream_name,
      target: "toasts",
      partial: "dashboard/shared/toast",
      locals: { id: "toast_#{SecureRandom.hex(6)}", level: level, message: message }
    )
  end

  def action_stream_name
    "app_#{id}_actions"
  end

  SUPPORTED_GIT_PROVIDERS = %w[github gitlab bitbucket].freeze

  validates :name, presence: true,
    uniqueness: { scope: :server_id },
    format: { with: /\A[a-z][a-z0-9-]*\z/, message: "must be lowercase alphanumeric with hyphens" }
  validates :git_provider, inclusion: { in: SUPPORTED_GIT_PROVIDERS }, allow_nil: true
  validates :git_repo_full_name, presence: true, if: -> { git_provider.present? }
  validates :pr_number, uniqueness: { scope: :parent_app_id }, if: :is_preview?

  scope :stale, -> { where("synced_at < ? OR synced_at IS NULL", 5.minutes.ago) }
  scope :main_apps, -> { where(is_preview: false) }
  scope :previews, -> { where(is_preview: true) }
  scope :preview_idle_for, ->(duration) { previews.where("last_commit_at < ?", duration.ago) }

  def preview_subdomain
    return nil unless is_preview? && parent_app && pr_number
    "#{parent_app.name}-pr-#{pr_number}"
  end

  def preview_hostname
    sub = preview_subdomain
    sub && "#{sub}.#{Wokku.config.canonical_domain}"
  end

  # Canonical git remote URL shown to users everywhere (dashboard, API,
  # CLI). Goes through the wokku SSH gateway rather than exposing the
  # underlying Dokku server IP.
  def git_remote_url
    # Default is the DEDICATED git gateway subdomain, never the web apex:
    # wokku.cloud/wokku.app may be Cloudflare-proxied and are not guaranteed
    # reachable on port 22 (see docs/infra/ssh-gateway.md). Prod sets this
    # env var explicitly; the default only bites dev/self-host fallbacks.
    host = ENV.fetch("WOKKU_GIT_HOST", "git.wokku.cloud")
    "git@#{host}:#{name}"
  end

  # Direct-to-Dokku URL. Still works and can be used as a bypass if the
  # gateway is down. Kept separately so we can display it in admin
  # views if needed.
  def direct_git_remote_url
    "dokku@#{server.host}:#{name}"
  end

  # Persistent volume attachments for converge. Mounts originate in template
  # metadata at deploy time, but converge also runs on restart/scale/sleep/
  # wake/tier changes, so the declaration lives on the record rather than
  # being recomputed from the template each time.
  #
  # One named volume per container path. The basename alone collides for
  # paths like /a/data and /b/data, so the full path is slugged.
  def mounts_for_converge
    Array(storage_mounts).map do |path|
      slug = path.to_s.gsub(%r{\A/|/\z}, "").gsub(%r{[^a-zA-Z0-9]+}, "-").presence || "data"
      { "volume" => "wokku-#{name}-#{slug}", "path" => path.to_s }
    end
  end
end
