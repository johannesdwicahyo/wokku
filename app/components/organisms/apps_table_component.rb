# frozen_string_literal: true

module Organisms
  # The apps index table. Extracted from AppsIndexComponent so it can be
  # rendered inside a deferred (lazy turbo-frame) section.
  class AppsTableComponent < ApplicationComponent
    # box_label delegates to ApplicationHelper#box_label_for (shared with the
    # record panel). Included directly rather than called via `helpers.` —
    # the component's spec calls #box_label on an unrendered instance, and
    # ViewComponent's `helpers` proxy needs a render context that doesn't
    # exist yet at that point.
    include ApplicationHelper

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

    # last_commit_at is only set for previews; the column showed "never"
    # for every normal app. One grouped query for the whole table.
    def last_deployed_at(app)
      @deployed_at ||= Deploy.where(app_record_id: apps.map(&:id), status: :succeeded)
                             .group(:app_record_id).maximum(:finished_at)
      @deployed_at[app.id] || (app.last_commit_at if app.respond_to?(:last_commit_at))
    end

    # The SIZE column shows the user-facing box vocabulary — delegates to
    # the shared ApplicationHelper#box_label_for so the record panel's Box
    # field can't drift from this table's SIZE column.
    def box_label(app)
      box_label_for(app)
    end

    # "18% · 410 MB · 4.2k req/24h" under the app name, or nil.
    def stats_line(app)
      @stats ||= ::Apps::ListStats.for(apps)
      ::Apps::ListStats.summary(@stats[app.id])
    end

    # First letter of the app name, uppercased — the schdl avatar mark.
    def app_mark(app)
      app.name.to_s[0].to_s.upcase
    end
  end
end
