# frozen_string_literal: true

module Organisms
  # Apps overview rack: one unit per app (status light, domain, size, CPU
  # light bars, last deploy) plus a crash alert under the rack.
  class AppsRackComponent < ApplicationComponent
    include ApplicationHelper

    CRASH_WINDOW = 10.minutes
    MAX_ALERTS = 3
    GRID = "grid-cols-[16px_minmax(0,1fr)_80px_20px] lg:grid-cols-[20px_minmax(0,1.6fr)_minmax(0,1.3fr)_110px_120px_90px_36px]"

    # {app_id => {count:, reason:}} for crashes in the window, one query.
    # reason = last non-blank line of the newest crash's log excerpt.
    def self.crashes_for(apps, since: CRASH_WINDOW.ago)
      rows = CrashEvent.where(app_record_id: apps.map(&:id), exited_at: since..)
                       .order(exited_at: :desc).pluck(:app_record_id, :log_excerpt)
      rows.group_by(&:first).transform_values do |list|
        { count: list.size, reason: list.first.last.to_s.lines.map(&:strip).reject(&:empty?).last&.truncate(120) }
      end
    end

    # {app_id => Time} of the latest succeeded deploy, one grouped query.
    def self.last_deploys_for(apps)
      Deploy.where(app_record_id: apps.map(&:id), status: :succeeded).group(:app_record_id).maximum(:finished_at)
    end

    def initialize(apps:, stats:, sparks:, last_deploys:, crashes: {})
      @apps = apps
      @stats = stats
      @sparks = sparks
      @last_deploys = last_deploys
      @crashes = crashes
    end

    attr_reader :sparks, :last_deploys, :crashes

    # Newest deploy first; never-deployed apps last, then by name.
    def apps
      @sorted ||= @apps.sort_by { |a| [ last_deploys[a.id] ? 0 : 1, -(last_deploys[a.id]&.to_f || 0), a.name ] }
    end

    def crashed?(app) = app.status.to_s == "crashed"

    def alerts = apps.select { |a| crashed?(a) }.first(MAX_ALERTS)

    def note(app)
      case app.status.to_s
      when "deploying" then t("apps.rack.note.deploying")
      when "sleeping" then t("apps.rack.note.sleeping")
      when "crashed" then (c = crashes[app.id]) && t("apps.rack.note.crashed", count: c[:count])
      end
    end

    def alert_text(app)
      reason = crashes.dig(app.id, :reason)
      reason.present? ? t("apps.rack.alert_reason", name: app.name, reason: reason) : t("apps.rack.alert", name: app.name)
    end

    def primary_domain(app)
      owned     = Wokku.config.owned_domains
      canonical = Wokku.config.canonical_domain
      custom    = app.domains.find { |d| owned.none? { |z| d.hostname.end_with?(".#{z}") } }
      wokku     = app.domains.find { |d| d.hostname.end_with?(".#{canonical}") } ||
                  app.domains.find { |d| owned.any? { |z| d.hostname.end_with?(".#{z}") } }
      (custom || wokku)&.hostname
    end

    def deployed_label(app)
      at = last_deploys[app.id]
      at ? time_ago(at) : t("apps.rack.never")
    end

    def cpu_label(app) = "#{app.name} #{t("apps.rack.cols.cpu")}"
  end
end
