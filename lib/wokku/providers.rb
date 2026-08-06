module Wokku
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

    attr_accessor :tls, :billing
    attr_writer :plan_enforcer, :dns_provider, :backup_store, :canonical_domain, :owned_domains, :require_admin_2fa, :open_registration

    def plan_enforcer
      @plan_enforcer ||= NullPlanEnforcer.new
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
