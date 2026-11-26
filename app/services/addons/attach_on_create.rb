module Addons
  # One attach path for add-ons: the databases page and the New app flow both
  # land here. Items are independent; a failure never raises or stops the rest.
  #
  #   {kind: "shared", engine:}
  #   {kind: "dedicated", engine:, shape: {cpu:, memory_mb:, disk_gb:}, alias_name: nil, name: nil, tier_name: nil}
  #   {kind: "existing", database_service_id:}
  #
  # Request-level gates (deposit, deletion-pending) stay with the caller.
  class AttachOnCreate
    MAX_ITEMS = 5

    # outcomes: [{item:, status:, db:}] in order; status is a Symbol
    # (:provisioned, :already_attached, :feature_disabled, :queued, :linked, ...).
    Result = Struct.new(:attached, :failed, :outcomes, keyword_init: true)

    def self.call(app:, user:, items:) = new(app: app, user: user, items: items).call

    # The one rule for "attach an existing DB": dedicated, running, same server,
    # and every linked app is in `team` (unlinked: its creator is a team member).
    # Shared tenants would share credentials and quota; cross-team links are refused.
    # The create form's list and #attach_existing both read this.
    def self.existing_candidates(user:, team:, server:)
      return [] unless server && team
      DatabaseServicePolicy::Scope.new(user, DatabaseService).resolve
        .where(server_id: server.id, shared: false, status: :running)
        .select do |db|
          teams = db.app_records.pluck(:team_id)
          teams.any? ? teams.all?(team.id) : team.users.exists?(id: db.creator_id)
        end
    end

    def initialize(app:, user:, items:)
      @app = app
      @user = user
      @items = Array(items).first(MAX_ITEMS)
    end

    def call
      result = Result.new(attached: [], failed: [], outcomes: [])
      @items.each do |raw|
        item = normalize(raw)
        outcome = safe_attach(item)
        result.outcomes << outcome.merge(item: item)
        if outcome[:error]
          result.failed << { label: label(item), error: outcome[:error] }
        elsif outcome[:status] != :feature_disabled
          result.attached << (outcome[:db]&.name || item[:engine].to_s)
        end
      end
      result
    end

    private

    ITEM_KEYS = %i[kind engine name tier_name alias_name database_service_id].freeze

    def normalize(raw)
      raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h) # ponytail: keys whitelisted below
      h = raw.to_h.symbolize_keys.slice(*ITEM_KEYS)
      shape = raw.to_h.symbolize_keys[:shape]
      h[:shape] = shape.to_h.symbolize_keys.slice(:cpu, :memory_mb, :disk_gb) if shape.present?
      h
    end

    # The never-raise contract lives here; the raw message stays in logs.
    def safe_attach(item)
      return fail_with(t("not_authorized")) unless Pundit.policy(@user, @app).update?
      attach(item)
    rescue => e
      Rails.logger.error("AttachOnCreate #{item[:kind]} failed: #{e.class}: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
      fail_with(t("failed"))
    end

    def attach(item)
      case item[:kind].to_s
      when "shared"    then attach_shared(item)
      when "dedicated" then attach_dedicated(item)
      when "existing"  then attach_existing(item)
      else fail_with(t("unknown_kind"))
      end
    end

    def attach_shared(item)
      status = Addons::SharedProvisioner.new(app: @app, engine: item[:engine]).call
      return { status: status } if %i[provisioned already_attached feature_disabled].include?(status)
      fail_with(t("shared_failed", engine: item[:engine], status: status.inspect), status: status)
    end

    def attach_dedicated(item)
      server = @app.server
      attrs = { service_type: item[:engine].to_s, name: item[:name], tier_name: item[:tier_name].presence || "basic",
                server: server, status: :creating, creator: @user }.compact

      # Per-resource billing (spec 2026-09-24 §5.3): same enforcer + capacity
      # checks ResizeService runs, via the shared Resources::ApplyChange helper.
      if item[:shape].present? && Wokku.config.resource_builder?
        s = item[:shape].to_h.symbolize_keys
        shape = Resources::Shape.new(cpu: s[:cpu], memory_mb: s[:memory_mb], disk_gb: s[:disk_gb])
        return fail_with(shape.errors(engine: attrs[:service_type]).join(", ")) unless shape.valid?(engine: attrs[:service_type])
        check = Resources::ApplyChange.check_new_shape(team: @app.team, server: server, shape: shape)
        return fail_with(check.error) unless check.ok
        attrs.merge!(cpu: shape.cpu, memory_mb: shape.memory_mb, disk_gb: shape.disk_gb)
      end

      attrs[:name] ||= default_name(server, attrs[:service_type])

      # Stuck error/creating rows from a prior failed attempt hold the unique
      # (server_id, name) slot; the row never got past provisioning, so sweep.
      if attrs[:name]
        DatabaseService.where(server: server, name: attrs[:name], status: [ :error, :creating ])
                       .where("created_at < ?", 5.minutes.ago).destroy_all
      end

      db = DatabaseService.new(attrs)
      return fail_with(t("not_authorized")) unless DatabaseServicePolicy.new(@user, db).create?
      unless db.save
        return fail_with(t("create_failed", message: db.errors.full_messages.to_sentence.presence || t("invalid_input")))
      end

      # Record-first: link now so deleting the app while the job is queued
      # tears this row down too, instead of orphaning it.
      begin
        DatabaseProvisioner.link!(@app, db)
        CreateAddonJob.perform_later(db.id, @app.id)
      rescue
        db.update(status: :error)
        raise
      end
      { status: :queued, db: db }
    end

    def attach_existing(item)
      db = self.class.existing_candidates(user: @user, team: @app.team, server: @app.server)
                 .find { |d| d.id.to_s == item[:database_service_id].to_s }
      return fail_with(t("unavailable")) unless db
      link_row = DatabaseProvisioner.link!(@app, db)
      DatabaseProvisioner.write_link_env!(@app, db, link_row)
      restart_if_running
      { status: :linked, db: db }
    end

    def restart_if_running
      ::Apps::Restarter.restart(@app) if @app.running?
    rescue => e
      Rails.logger.warn "Restart after attach failed for #{@app.name}: #{e.message}"
    end

    # Same convention as DatabaseProvisioner#default_name; suffix on collision.
    def default_name(server, engine)
      base = "#{@app.name}-#{engine}"
      DatabaseService.exists?(server: server, name: base) ? "#{base}-#{SecureRandom.hex(2)}" : base
    end

    def fail_with(error, **extra) = { error: error, status: :failed, **extra }

    def label(item)
      return item[:engine] if item[:kind].to_s != "existing" && item[:engine].present?
      DatabaseServicePolicy::Scope.new(@user, DatabaseService).resolve.find_by(id: item[:database_service_id])&.name ||
        I18n.t("new_app.addons.existing_label")
    end

    def t(key, **opts) = I18n.t("new_app.attach.#{key}", **opts)
  end
end
