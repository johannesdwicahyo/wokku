module Wokku
  # Is this the managed wokku.cloud (billing host attached) rather than a
  # self-host install? The single check for cloud-only copy, links and
  # features — the billing host draws dashboard_billing, self-host never does.
  def self.cloud?
    Rails.application.routes.named_routes.key?(:dashboard_billing)
  end

  # Who users should contact: wokku.cloud's support desk, or on self-host
  # the install's admin (there is no wokku.cloud desk for them).
  def self.support_email
    return "support@wokku.cloud" if cloud?
    User.find_by(role: :admin)&.email || "your administrator"
  end

  # Dependency-injection seam between the OSS engine and the managed host app.
  # The engine calls Wokku.config.<provider>; OSS ships null/local defaults,
  # wokku-cloud injects managed implementations via Wokku.configure at boot.
  class Providers
    # Seam-level DNS failure: dns_provider implementations wrap their
    # client-specific errors (e.g. Cloudflare::Dns::ApiError) into this so
    # engine rescuers never name a managed constant.
    DnsError = Class.new(StandardError)

    # OSS default: no plan limits. Managed injects Billing::PlanEnforcer.
    class NullPlanEnforcer
      def allowed?(*, **) = true
      def quota(_owner, _kind, _key = nil) = Float::INFINITY
      def deposit_shortfall(_user, **) = nil
    end

    # OSS default: no prices anywhere. Managed injects Billing::PricingProvider.
    class NullPricing
      def monthly_idr(_shape, instances: 1) = nil
      def unit_prices = nil
      # A scheduled unit-price increase, or nil: { effective_on: Date,
      # from: unit_prices-shaped hash, to: unit_prices-shaped hash }.
      def upcoming_change = nil
    end

    attr_accessor :tls, :billing
    attr_writer :plan_enforcer, :dns_provider, :backup_store, :canonical_domain, :owned_domains, :require_admin_2fa, :open_registration, :pricing, :resource_builder, :host_ssh_user, :control_plane_host, :openapi_path, :object_storage, :sidebar_extra_items, :addon_path_prefixes, :app_resource_sections, :object_storage_limits, :addons_index_sections, :apps_index_readouts, :apps_index_side_sections, :object_storage_pricing_note, :image_scans

    # The OpenAPI file GET /api/v1/openapi.yaml serves. Engine default: its
    # own derived contract; the cloud points it at the cloud superset.
    def openapi_path
      @openapi_path || Wokku::Engine.root.join("openapi/v1.yaml")
    end

    # Extension point for host apps: a callable taking the view context and
    # returning extra rail items (label:, key:, href:, active:, count:; optional
    # group: :workspace | :account, anything else means :workspace; icon: ignored). Default adds none.
    def sidebar_extra_items
      @sidebar_extra_items || ->(_view) { [] }
    end

    # Path prefixes that mark the rail's Add-ons item active (a host app whose
    # add-on pages live elsewhere adds its own). Default: the engine's page.
    def addon_path_prefixes
      @addon_path_prefixes || [ "/dashboard/addons" ]
    end

    # Extension point for host apps: a callable taking the view context and the
    # app, returning extra Resources-page sections as
    # [{ partial: "path/to/partial", locals: { ... } }, ...]. Default adds none.
    def app_resource_sections
      @app_resource_sections || ->(_view, _app) { [] }
    end

    # Extension point for host apps: a callable taking the view context and the
    # team, returning extra sections for the top of the Add-ons page, same shape
    # as app_resource_sections. Default adds none.
    def addons_index_sections
      @addons_index_sections || ->(_view, _team) { [] }
    end

    # Extension point for host apps: a callable taking the view context and the
    # team, returning extra Overview readouts as [{ label:, value:, sub: }].
    # Call via Organisms::AppsOverviewComponent.readouts_for (rescues + filters).
    def apps_index_readouts
      @apps_index_readouts || ->(_view, _team) { [] }
    end

    # Extension point for host apps: a callable taking the view context and the
    # team, returning extra Apps side-column sections, same shape as
    # addons_index_sections. Call via Organisms::AppsSideComponent.sections_for
    # (rescues + filters). Default adds none.
    def apps_index_side_sections
      @apps_index_side_sections || ->(_view, _team) { [] }
    end

    # Object-storage plan limits for a team: { free: Boolean, max_buckets:
    # Integer|nil, max_bucket_gb: Integer|nil } (nil = unlimited; the GB cap is per bucket). Default is
    # the stock behaviour: free plan = one 1 GB bucket, paid = unlimited.
    def object_storage_limits
      @object_storage_limits || ->(team) {
        free = !!team.current_plan&.free?
        { free: free, max_buckets: nil, max_bucket_gb: (ObjectStorageBucket::FREE_QUOTA_GB if free) }
      }
    end

    # (team) -> String|nil. Host-supplied pricing text appended to the object-storage
    # copy (card, section, usage page, API). Default: no price text (self-host).
    def object_storage_pricing_note
      @object_storage_pricing_note || ->(_team) { nil }
    end

    # {endpoint:, access_key:, secret_key:} for the object-storage (RustFS)
    # add-on; nil (OSS default) means the add-on is unavailable.
    def object_storage = @object_storage.presence

    def object_storage? = @object_storage.present?

    def plan_enforcer
      @plan_enforcer ||= NullPlanEnforcer.new
    end

    def pricing
      @pricing ||= NullPricing.new
    end

    # Per-resource slider builder vs the legacy box-tier picker. Self-host
    # has no plans, so it's on; the cloud flips it with its billing launch.
    def resource_builder?
      @resource_builder.nil? ? true : @resource_builder
    end

    # Tier 0 image vulnerability scans on every deploy. Off until a host
    # app (or self-host admin) opts in.
    def image_scans?
      @image_scans || false
    end

    def dns_provider
      @dns_provider ||= NullDnsProvider.new
    end

    def backup_store
      @backup_store ||= LocalBackupStore.new
    end

    # Self-host default: admin 2FA is optional (opt-in enforcement via
    # env); the managed cloud sets this true at boot.
    def require_admin_2fa
      return @require_admin_2fa unless @require_admin_2fa.nil?
      ENV["WOKKU_REQUIRE_ADMIN_2FA"] == "1"
    end

    # Self-host default: registration is CLOSED — a private control plane
    # must not let anyone with a GitHub account self-register the moment
    # OAuth creds are configured. Existing accounts still sign in (and
    # get their OAuth linked by email). Opt into open signup with
    # WOKKU_OPEN_REGISTRATION=1; the cloud sets true at boot (public SaaS).
    def open_registration
      return @open_registration unless @open_registration.nil?
      ENV["WOKKU_OPEN_REGISTRATION"] == "1"
    end

    # OSS default: one env var names the install's apex; apps live at
    # <app>.<canonical>. *.localhost resolves to 127.0.0.1 in browsers, so
    # the zero-config self-host still gets working URLs.
    def canonical_domain
      @canonical_domain ||= ENV.fetch("WOKKU_CANONICAL_DOMAIN", "localhost")
    end

    # SSH login for platform access to app hosts. Self-host default is root
    # (no helpers installed); the cloud sets a docker-group user that
    # reaches the few root-only ops through sudo'd /usr/local/sbin helpers.
    def host_ssh_user
      @host_ssh_user.presence || "root"
    end

    # Host the dashboard answers on — the wake proxy's upstream. Self-host
    # serves the dashboard on the canonical apex; the cloud markets apps on
    # wokku.app but its control plane only answers on wokku.cloud. No memo,
    # same reason as owned_domains.
    def control_plane_host
      @control_plane_host.presence || canonical_domain
    end

    def owned_domains
      # No memo: a memoized default here goes stale if canonical_domain is
      # injected after the first read.
      @owned_domains || [ canonical_domain ]
    end
  end

  class << self
    # Configured once at boot (host app's Wokku.configure in an initializer),
    # read-only thereafter — same contract as Rails.application.config. The
    # lazy `||=` is not thread-safe, which is safe only under that invariant:
    # never mutate providers after the first request thread starts.
    def config
      @config ||= Providers.new
    end

    def configure
      yield config
    end
  end
end
