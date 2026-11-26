module Addons
  # Bundle v2 (backlog 2.8) — produces the (engine, mode) options that
  # render the "Add database / cache / queue" picker on both
  # /dashboard/addons/new and the in-app slide-panel
  # /dashboard/apps/:id/resources.
  #
  # Replaces the legacy ServiceTier-based picker (basic / standard /
  # performance) that no longer matches the Bundle v2 product. Under
  # Bundle v2 the user picks an engine and one of two modes:
  #
  #   shared    — logical tenant on a per-server host container,
  #               included free with every paid plan. Provisioned by
  #               Addons::SharedProvisioner.
  #   dedicated — its own dokku-<engine> container, you size it. Consumes one of 3 dedicated
  #               slots on Pro/Team. Provisioned by DatabaseProvisioner.
  #
  # Some engines only support one mode for now — mongodb only has a
  # dedicated path. Every shared mode is free on every plan (2026-10-05):
  # postgres, mariadb, redis. rabbitmq + meilisearch left the offering
  # 2026-10-05 (zero tenants in prod); memcached 2026-10-06 (no isolation).
  # mysql is dedicated-only: the free shared SQL tier stays MariaDB (Laravel
  # runs on either). Retired 07-09, back 2026-11-03.
  class PickerOptions
    ENGINES = [
      { key: "postgres",      label: "PostgreSQL",   modes: %w[shared dedicated] },
      { key: "redis",         label: "Redis",        modes: %w[shared dedicated] },
      { key: "mariadb",       label: "MariaDB",      modes: %w[shared dedicated] },
      { key: "mysql",         label: "MySQL",        modes: %w[dedicated] },
      { key: "mongodb",       label: "MongoDB",      modes: %w[dedicated] }
      # elasticsearch pulled 2026-07-15: dokku-elasticsearch has no
      # export/import, so an ES service would be unbackable (needs ES
      # snapshot-API work). Re-add on real demand.
    ].freeze

    # Copy lives in config/locales/*/addons.yml (addons.picker.*).
    SHORTCUT_KEYS = Resources::Shape::DB_SHORTCUTS.keys.freeze

    def self.for_user(user)
      new(user).call
    end

    # Typed list for the create page: engines -> modes -> env var + valid
    # size shortcuts. Built from for_user.
    def self.catalog(user)
      for_user(user).map do |key, engine|
        {
          key: key, label: engine[:label],
          modes: engine[:modes].map do |m|
            m.slice(:mode, :available, :unavailable_reason).merge(
              env_vars: env_vars(key, m[:mode]),
              shortcuts: m[:mode] == "dedicated" ? shortcuts(key) : []
            )
          end
        }
      end
    end

    # What an attach really writes on a new app, read off the provisioner's own
    # naming (dedicated: <TYPE>_URL + postgres' DATABASE_URL; shared: tenant env).
    def self.env_vars(engine, mode)
      if mode == "dedicated"
        DatabaseProvisioner.dedicated_env(AppRecord.new, DatabaseService.new(service_type: engine, dsn: "x")).keys
      else
        DatabaseProvisioner.shared_sql_env(engine, "x").keys.presence ||
          DatabaseProvisioner::SHARED_TENANT_ENV_KEYS.fetch(engine) { [ "#{engine.upcase}_URL" ] }
      end
    end

    # A shortcut the engine's Shape rules reject (e.g. 256 MB mysql) is omitted.
    def self.shortcuts(engine)
      Resources::Shape::DB_SHORTCUTS.filter_map do |k, v|
        shape = Resources::Shape.new(**v)
        { key: k, shape: shape.to_h } if shape.valid?(engine: engine)
      end
    end

    def initialize(user)
      @user  = user
      @plan  = user&.current_plan
    end

    # Returns a hash keyed by engine slug: { "postgres" => { label:, modes: [...] }, ... }
    # Each mode entry includes the user-plan-aware availability so the
    # JS can render disabled cards with the reason inline.
    def call
      ENGINES.each_with_object({}) do |engine, h|
        h[engine[:key]] = {
          label: engine[:label],
          # Dedicated-only where the install runs no shared engines (the
          # open-source edition): shared isn't offered at all.
          modes: engine[:modes].select { |m| m != "shared" || Addons::SharedProvisioner.feature_enabled? }
                               .map { |m| mode_entry(engine[:key], m) }
        }
      end
    end

    private

    def mode_entry(engine, mode)
      copy = if !Wokku.cloud? then "self_host"
      elsif mode == "dedicated" && Wokku.config.resource_builder? then "per_resource"
      else "default"
      end
      t = ->(k) { I18n.t("addons.picker.#{k}") }
      avail = availability(engine, mode)
      {
        label: t.("#{mode}.label"),
        kicker: t.("#{mode}.#{copy}.kicker"),
        description: t.("#{mode}.#{copy}.description"),
        mode: mode, available: avail[:ok], unavailable_reason: avail[:reason]
      }
    end

    def availability(engine, mode)
      case mode
      when "shared"
        # Free + paid all get shared today (Bundle v2 spec). Only listed
        # where shared engines run (see for_user).
        { ok: true, reason: nil }
      when "dedicated"
        if Wokku.config.resource_builder?
          { ok: true, reason: nil }
        elsif @plan.nil? || @plan.free?
          { ok: false, reason: I18n.t("addons.picker.upgrade") }
        elsif !@plan.offers_dedicated?(engine)
          { ok: false, reason: I18n.t("addons.picker.unavailable", engine: engine) }
        else
          { ok: true, reason: nil }
        end
      end
    end
  end
end
