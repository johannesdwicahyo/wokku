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
  #   dedicated — its own dokku-<engine> container, sized by the
  #               user's plan box size. Consumes one of 3 dedicated
  #               slots on Pro/Team. Provisioned by DatabaseProvisioner.
  #
  # Some engines only support one mode for now — mongodb only has a
  # dedicated path; memcached only has shared. Every shared mode is free on
  # every plan (2026-10-05): postgres, mariadb, redis, memcached. rabbitmq + meilisearch
  # left the offering 2026-10-05 (zero tenants in prod).
  # mysql retired 2026-07-09 (dedicated MySQL retired, see
  # DatabaseService::RETIRED_TYPES) — not offered here for new services.
  class PickerOptions
    ENGINES = [
      { key: "postgres",      label: "PostgreSQL",   modes: %w[shared dedicated] },
      { key: "redis",         label: "Redis",        modes: %w[shared dedicated] },
      { key: "memcached",     label: "Memcached",    modes: %w[shared] },
      { key: "mariadb",       label: "MariaDB",      modes: %w[shared dedicated] },
      { key: "mongodb",       label: "MongoDB",      modes: %w[dedicated] }
      # elasticsearch pulled 2026-07-15: dokku-elasticsearch has no
      # export/import, so an ES service would be unbackable (needs ES
      # snapshot-API work). Re-add on real demand.
    ].freeze

    MODE_COPY = {
      "shared" => {
        label:       "Shared",
        kicker:      "Free, included",
        description: "Logical tenant on a per-server host container. Auto-attaches DATABASE_URL. No extra cost."
      },
      "dedicated" => {
        label:       "Dedicated",
        kicker:      "Paid plan",
        description: "Its own Dokku container, sized by your plan's box. Consumes 1 of 3 dedicated slots."
      }
    }.freeze

    def self.for_user(user)
      new(user).call
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
          modes: engine[:modes].map { |m| mode_entry(engine[:key], m) }
        }
      end
    end

    private

    def mode_entry(engine, mode)
      base = MODE_COPY.fetch(mode).dup
      avail = availability(engine, mode)
      base.merge(mode: mode, available: avail[:ok], unavailable_reason: avail[:reason])
    end

    def availability(engine, mode)
      case mode
      when "shared"
        # Free + paid all get shared today (Bundle v2 spec).
        { ok: true, reason: nil }
      when "dedicated"
        if @plan.nil? || @plan.free?
          { ok: false, reason: "Upgrade to Solo or higher for dedicated databases" }
        elsif !@plan.offers_dedicated?(engine)
          { ok: false, reason: "Dedicated #{engine} not yet available on your plan" }
        else
          { ok: true, reason: nil }
        end
      end
    end
  end
end
