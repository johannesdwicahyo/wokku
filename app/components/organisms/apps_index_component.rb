module Organisms
  class AppsIndexComponent < ApplicationComponent
    def initialize(apps:, plan:, box_usage:, recent_activity:)
      @apps = apps
      @plan = plan
      @box_usage = box_usage
      @recent_activity = recent_activity
    end
    attr_reader :apps, :plan, :box_usage, :recent_activity

    def empty?
      apps.empty?
    end

    # Best domain to display: prefer a custom domain, then any Wokku-owned
    # subdomain (canonical first, then the legacy one). Falls back to nil
    # when no domains are attached.
    def primary_domain(app)
      owned     = Cloudflare::Dns.owned_domains
      canonical = Cloudflare::Dns.canonical_domain
      custom    = app.domains.find { |d| owned.none? { |z| d.hostname.end_with?(".#{z}") } }
      wokku     = app.domains.find { |d| d.hostname.end_with?(".#{canonical}") } ||
                  app.domains.find { |d| owned.any? { |z| d.hostname.end_with?(".#{z}") } }
      (custom || wokku)&.hostname
    end

    # Last activity timestamp: use last_commit_at if present, else nil.
    def last_deployed_at(app)
      app.respond_to?(:last_commit_at) ? app.last_commit_at : nil
    end
  end
end
