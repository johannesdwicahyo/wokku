# frozen_string_literal: true

module Organisms
  # The apps index table. Extracted from AppsIndexComponent so it can be
  # rendered inside a deferred (lazy turbo-frame) section.
  class AppsTableComponent < ApplicationComponent
    def initialize(apps:)
      @apps = apps
    end

    attr_reader :apps

    def primary_domain(app)
      owned     = Wokku.config.owned_domains
      canonical = Wokku.config.canonical_domain
      custom    = app.domains.find { |d| owned.none? { |z| d.hostname.end_with?(".#{z}") } }
      wokku     = app.domains.find { |d| d.hostname.end_with?(".#{canonical}") } ||
                  app.domains.find { |d| owned.any? { |z| d.hostname.end_with?(".#{z}") } }
      (custom || wokku)&.hostname
    end

    def last_deployed_at(app)
      app.respond_to?(:last_commit_at) ? app.last_commit_at : nil
    end

    # The SIZE column shows the user-facing box vocabulary
    # (sleeping/small/medium/large/xlarge), translated from the app's web
    # DynoTier name (free/basic/standard/...) via the canonical map.
    def box_label(app)
      tier = app.dyno_allocations.find { |d| d.process_type == "web" }&.dyno_tier
      return "—" unless tier

      DynoTier::DYNO_TIER_TO_BOX_SIZE[tier.name] || tier.name
    end
  end
end
