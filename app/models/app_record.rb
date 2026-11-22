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

  # A failed deploy means "crashed" only if a release ever ran. An app whose
  # deploys have all failed stays :created ("Not deployed") — nothing crashed.
  def mark_deploy_failed!
    update!(status: deploys.succeeded.exists? ? :crashed : :created)
  end

  # What lists show: a never-deployed app whose latest deploy failed is
  # "Deploy failed", not "Not deployed" (which hid the failure).
  def display_status
    return status.to_s unless created?
    deploys.order(created_at: :desc).pick(:status).to_s.in?(%w[failed timed_out]) ? "deploy_failed" : "created"
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

  RUN_BLOCKED_MESSAGE = "This account is suspended for an unpaid invoice — pay it to restart your apps.".freeze

  # Seam gate for anything that brings the app UP (start/restart/deploy/
  # rollback). OSS NullPlanEnforcer always allows; the managed enforcer
  # refuses while the team owner is billing-suspended.
  # Lowercased owner of the deploy repo ("owner" of owner/repo or of an
  # https/ssh git URL), nil when unknown. Used to spot banned owners.
  def repo_owner
    ref = git_repo_full_name.presence || github_repo_full_name.presence || git_repository_url.to_s
    ref.strip[%r{\A(?:(?:https?://|git@)[^/:]+[/:])?([^/:\s]+)/[^/\s]+\z}, 1]&.downcase
  end

  def run_allowed?
    return false if team&.owner&.abuse_suspended?

    Wokku.config.plan_enforcer.allowed?(team, :run_apps)
  end

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
  # Telemetry tables: no callbacks or children, and an app holds thousands
  # of rows. :destroy deleted them one by one (18k queries, 53 s → 504).
  has_many :logs, dependent: :delete_all
  has_many :request_samples, dependent: :delete_all
  has_many :request_aggregates, dependent: :delete_all
  has_many :metric_hourly, dependent: :delete_all
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
  has_many :metrics, dependent: :delete_all
  has_many :notifications, dependent: :destroy
  has_many :dyno_allocations, dependent: :destroy
  has_many :scheduled_tasks, dependent: :destroy
  has_many :vitals_events,         dependent: :delete_all
  has_many :vitals_hourly_rollups, dependent: :delete_all
  has_many :crash_events,          dependent: :delete_all
  has_many :app_transfers,         dependent: :delete_all
  has_many :incidents,             dependent: :destroy
  has_many :lifecycle_ops,         dependent: :destroy
  has_one :preview_dns_record, dependent: :destroy
  has_one :object_storage_bucket, dependent: nil

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
  # Strip blank/whitespace entries (e.g. the create-app form's empty hidden
  # input submitted when no shared engine is checked, which arrives as [""]).
  # An empty string is "no selection", not an unknown engine — normalizing
  # here covers the form, API, and console before validation runs.
  normalizes :enabled_shared_engines, with: ->(v) { Array(v).map { |e| e.to_s.strip }.reject(&:blank?) }
  validate :enabled_shared_engines_subset_of_known

  def shared_engine_enabled?(engine)
    enabled_shared_engines.include?(engine.to_s)
  end

  private

  # Only NEWLY added entries must be known: an engine retired from the
  # offering (rabbitmq/meilisearch, 2026-10-05) may linger on old rows and
  # must not make every later save of that app fail.
  def enabled_shared_engines_subset_of_known
    extras = Array(enabled_shared_engines).map(&:to_s) - Array(enabled_shared_engines_was).map(&:to_s) - SHARED_ENGINES
    errors.add(:enabled_shared_engines, "unknown engine(s): #{extras.join(', ')}") if extras.any?
  end

  public

  # True when the web process runs on a free sleeping tier (unshaped) —
  # distinguishes an idle-slept free app from a billing-suspended paid one,
  # which shares status: sleeping.
  def sleeping_tier?
    dyno_allocations.find { |a| a.process_type == "web" }&.sleeping? || false
  end

  # Wake-on-request: unguessable, non-expiring token naming this app in the
  # /__wake/<token> path its sleeping vhosts proxy to.
  def wake_token = Rails.application.message_verifier(:wake).generate(id, purpose: :wake)

  def self.find_by_wake_token(token)
    id = Rails.application.message_verifier(:wake).verified(token.to_s, purpose: :wake)
    id && find_by(id: id)
  end

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

  # Platform subdomains on the managed zone. An app's name becomes
  # <name>.<zone>'s DNS record, and deleting the app deletes that record —
  # an app named `git` would take down git.wokku.cloud.
  RESERVED_NAMES = %w[s3 git cdn www status].freeze

  validates :name, presence: true,
    uniqueness: { scope: :server_id },
    format: { with: /\A[a-z][a-z0-9-]*\z/, message: "must be lowercase alphanumeric with hyphens" },
    exclusion: { in: RESERVED_NAMES, message: "is reserved" }
  validates :git_provider, inclusion: { in: SUPPORTED_GIT_PROVIDERS }, allow_nil: true
  # PR preview database: empty, snapshot of prod, or shared with prod.
  PREVIEW_DATABASE_STRATEGIES = %w[empty snapshot shared].freeze
  validates :database_strategy, inclusion: { in: PREVIEW_DATABASE_STRATEGIES }
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
  # nil when this install runs no git SSH gateway (self-host by default):
  # views and the API then hide git-push instructions instead of pointing
  # users at someone else's server. wokku.cloud sets WOKKU_GIT_HOST.
  def git_remote_url
    host = self.class.git_gateway_host
    host && "git@#{host}:#{name}"
  end

  # The DEDICATED git gateway host, never the web apex (wokku.cloud may be
  # Cloudflare-proxied and not reachable on port 22; docs/infra/ssh-gateway.md).
  def self.git_gateway_host
    ENV["WOKKU_GIT_HOST"].presence
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

  # Bytes → GB from the wokkud heartbeat's hourly volume_usage (spec §6).
  # nil when the host hasn't reported (never guess — billing falls back to
  # the allocated size).
  def volume_used_gb
    usage = server&.vitals&.dig("volume_usage")
    return nil unless usage
    bytes = mounts_for_converge.sum { |m| usage["/var/lib/docker/volumes/#{m['volume']}/_data"].to_i }
    (bytes / 1024.0**3).round(2)
  end
end
