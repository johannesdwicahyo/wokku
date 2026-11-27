# frozen_string_literal: true

module Organisms
  # Add-ons index rack: one panel per group (by type / by app), rows in the
  # apps-rack look, plus optional orphan and object-storage sections. Rows
  # come from dashboard/databases/_addon_card, which is also the Turbo Stream
  # replace/insert target (DatabaseService#broadcast_*).
  class AddonsRackComponent < ApplicationComponent
    GRID = "grid-cols-[16px_minmax(0,1fr)_auto] lg:grid-cols-[20px_minmax(0,1.4fr)_minmax(0,1.2fr)_minmax(0,1fr)_130px_auto]"
    BUCKET_GRID = "grid-cols-[16px_minmax(0,1fr)_auto] lg:grid-cols-[20px_minmax(0,1.4fr)_minmax(0,1fr)_minmax(0,1fr)]"
    HEAD = "hidden lg:grid gap-4 px-[18px] py-2.5 border-b border-line font-mono text-[11px] uppercase tracking-[.12em] text-muted"
    LIGHTS = {
      "running" => :running, "stopped" => :stopped, "pending_destroy" => :stopped,
      "creating" => :deploying, "upgrading_provisioning" => :deploying,
      "upgrading_migrating" => :deploying, "upgrading_cutover" => :deploying,
      "error" => :crashed, "upgrading_failed" => :crashed
    }.freeze

    def self.light_state(status) = LIGHTS.fetch(status.to_s, :created)

    def self.backups_label(addon)
      key = if addon.backups_unsupported? then "none"
      elsif addon.auto_backup? then "nightly"
      else "manual"
      end
      I18n.t("dashboard.databases.rack.backups.#{key}")
    end

    def initialize(databases:, group_by:, apps:, orphans: [], buckets: [])
      @databases, @group_by, @apps, @orphans, @buckets = databases, group_by.to_s, apps, orphans, buckets
    end

    attr_reader :orphans, :buckets

    def by_app? = @group_by == "app"

    # [[title, [dbs]], ...]. Orphans live in their own section, so they are
    # left out here; by app, a db shows under each app it is linked to.
    def groups
      dbs = @databases - orphans
      if by_app?
        @apps.filter_map { |a| (list = dbs.select { |d| d.app_records.include?(a) }).any? && [ a.name, list ] }
      else
        dbs.group_by(&:service_type).map { |type, list| [ type.to_s.titleize, list ] }
      end
    end

    # Turbo broadcasts (replace/remove) hit only the first element with
    # dom_id(addon), so only the first rendering of a db carries the bare id;
    # repeats (by-app, db linked to several apps) get a scoped one.
    def render_rows(dbs, scope)
      @seen ||= Set.new
      safe_join(dbs.map do |db|
        id = @seen.add?(db.id) ? nil : "#{helpers.dom_id(db)}_#{scope}"
        render(partial: "dashboard/databases/addon_card", locals: { addon: db, row_id: id })
      end)
    end

    def toggle_class(pressed)
      "px-3.5 py-1.5 font-mono text-[11px] uppercase tracking-[.12em] transition-colors " +
        (pressed ? "bg-white/10 text-ink" : "text-muted hover:text-ink")
    end

    def meter_on(bucket) = bucket.quota_gb.to_f.positive? ? (bucket.used_gb.to_f / bucket.quota_gb * 10).ceil : 0
    def meter_tone(bucket) = bucket.quota_gb.to_f.positive? && bucket.used_gb.to_f / bucket.quota_gb >= 0.8 ? :warn : :ink
    def bucket_light(bucket) = bucket.status.to_s == "ready" ? :running : (bucket.status.to_s == "error" ? :crashed : :deploying)
  end
end
