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

    def initialize(app:, user:, items:)
      @app = app
      @user = user
      @items = Array(items).first(MAX_ITEMS)
    end

    def call
      result = Result.new(attached: [], failed: [], outcomes: [])
      @items.each do |raw|
        item = raw.to_h.symbolize_keys
        outcome = attach(item)
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

    def attach(item)
      case item[:kind].to_s
      when "shared"    then attach_shared(item)
      when "dedicated" then attach_dedicated(item)
      when "existing"  then attach_existing(item)
      else fail_with("Unknown add-on kind")
      end
    end

    def attach_shared(item)
      status = Addons::SharedProvisioner.new(app: @app, engine: item[:engine]).call
      return { status: status } if %i[provisioned already_attached feature_disabled].include?(status)
      fail_with("Couldn't attach shared #{item[:engine]}: #{status.inspect}.", status: status)
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
      unless db.save
        return fail_with("Couldn't create add-on: #{db.errors.full_messages.to_sentence.presence || 'invalid input'}.")
      end

      begin
        # Record-first: link now so deleting the app while the job is queued
        # tears this row down too, instead of orphaning it.
        DatabaseProvisioner.link!(@app, db)
        CreateAddonJob.perform_later(db.id, @app.id)
      rescue => e
        db.update(status: :error)
        return fail_with("Failed to create add-on: #{e.message}", db: db)
      end
      { status: :queued, db: db }
    rescue => e
      fail_with("Failed to create add-on: #{e.message}")
    end

    def attach_existing(item)
      db = DatabaseServicePolicy::Scope.new(@user, DatabaseService).resolve
             .find_by(id: item[:database_service_id], server_id: @app.server_id)
      return fail_with("Add-on not available") unless db
      DatabaseProvisioner.link!(@app, db)
      { status: :linked, db: db }
    rescue => e
      fail_with("Failed to attach add-on: #{e.message}")
    end

    # Same convention as DatabaseProvisioner#default_name; suffix on collision.
    def default_name(server, engine)
      base = "#{@app.name}-#{engine}"
      DatabaseService.exists?(server: server, name: base) ? "#{base}-#{SecureRandom.hex(2)}" : base
    end

    def fail_with(error, **extra) = { error: error, status: :failed, **extra }

    def label(item) = item[:engine].presence || item[:database_service_id].to_s
  end
end
