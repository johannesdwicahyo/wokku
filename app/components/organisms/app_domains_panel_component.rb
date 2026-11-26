# frozen_string_literal: true

module Organisms
  # Custom domains with their HTTPS state (same states as domains/_row),
  # then the platform address.
  class AppDomainsPanelComponent < ApplicationComponent
    def initialize(app:, domains:)
      @app, @domains = app, domains.to_a
    end
    attr_reader :app

    def custom = @domains.reject { |d| d.wildcard? || d.managed_subdomain? }.sort_by(&:hostname)
    def platform = AppHeaderComponent.platform_address(app)

    def tag(domain)
      return [ t("apps.domains.https"), "text-live" ] if domain.ssl_enabled?
      domain.dns_verified? ? [ t("apps.domains.no_https"), "text-muted" ] : [ t("apps.domains.pending_dns"), "text-warn" ]
    end
  end
end
