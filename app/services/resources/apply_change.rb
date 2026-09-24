module Resources
  # The one write path for per-resource sizing (dashboard, API, create-app).
  # Validates → plan_enforcer :resources → capacity → persist → converge.
  class ApplyChange
    Result = Struct.new(:ok, :error, keyword_init: true)
    Rejected = Class.new(StandardError)
    DISABLED = "Custom sizing is not enabled on this server.".freeze

    def self.disabled = Result.new(ok: false, error: DISABLED)

    # Capacity refusals mail ops at most once per server per hour. Called
    # after any transaction (a deliver_later enqueued inside a rolled-back
    # transaction is dropped).
    def self.notify_capacity_full(server)
      return unless Rails.cache.write("capacity-full:#{server.id}", true, expires_in: 1.hour, unless_exist: true)
      OpsMailer.capacity_full(server).deliver_later
    end

    # Count-only changes (scaling UI / legacy API) routed through #call.
    # Sleeping allocations stay sleeping; everything else keeps the size
    # inherited_shape_for resolves.
    def self.processes_for_counts(app, counts)
      allocs = app.dyno_allocations.includes(:dyno_tier).index_by(&:process_type)
      counts.to_h do |type, count|
        spec = if allocs[type.to_s]&.sleeping? then { sleeping: true }
        else inherited_shape_for(app, type, allocs).to_h.slice(:cpu, :memory_mb)
        end
        [ type.to_s, spec.merge(count: count) ]
      end
    end

    # The shape a process keeps when only its count changes: its own shape;
    # else its non-sleeping legacy tier's size rounded up onto the grid;
    # else web's by the same rule; else Starter. Legacy tiers must never
    # silently shrink to Starter on a scale.
    def self.inherited_shape_for(app, process_type, allocs = nil)
      allocs ||= app.dyno_allocations.includes(:dyno_tier).index_by(&:process_type)
      own_or_tier = lambda do |a|
        next unless a
        next a.shape if a.shape
        Shape.round_up(cpu: a.effective_cpu, memory_mb: a.effective_memory_mb) unless a.sleeping? || a.dyno_tier.nil?
      end
      own_or_tier.(allocs[process_type.to_s]) || own_or_tier.(allocs["web"]) || Shape.new(**Shape::PRESETS["starter"])
    end

    def self.call(**) = new(**).call

    # Team-wide [{shape:, instances:, service_id:|volume_app_id:}] for the
    # enforcer's before/after view — shaped processes, app volume disks (a
    # disk-only shape, never validated), AND shaped dedicated services.
    def self.team_allocations(team)
      procs = AppRecord.where(team: team).includes(:process_scales, :dyno_allocations).flat_map do |app|
        scales = app.process_scales.index_by(&:process_type)
        allocs = app.dyno_allocations.filter_map do |a|
          next unless a.shape
          { shape: a.shape, instances: scales[a.process_type]&.count || (a.process_type == "web" ? 1 : 0) }
        end
        next allocs unless app.volume_disk_gb.to_i.positive?
        allocs + [ { shape: Shape.new(cpu: 0, memory_mb: 0, disk_gb: app.volume_disk_gb), instances: 1, volume_app_id: app.id } ]
      end
      linked_services = DatabaseService.where(shared: false).where.not(cpu: nil)
        .joins(:app_records).where(app_records: { team_id: team.id }).distinct
      # Not every shaped dedicated service is linked to an app yet — a
      # not-yet-linked datastore is still billed to its creator's team
      # (DatabaseService#billing_team), so it must count here too, or the
      # enforcer's before/after view never sees it (review fix round 1).
      # SQL narrows to "created by a member of this team" (cheap), then
      # #billing_team resolves the actual team it bills to — a creator on
      # several teams must only count it toward ONE of them, else it's
      # double-counted across every team they belong to (review fix
      # round 2).
      unlinked_services = DatabaseService.where(shared: false).where.not(cpu: nil)
        .where.missing(:app_databases).where(creator_id: team.users.select(:id))
        .select { |db| db.billing_team == team }
      services = (linked_services.to_a + unlinked_services).uniq(&:id)
      procs + services.map { |db| { shape: db.shape, instances: 1, service_id: db.id } }
    end

    # Enforcer + capacity check for a shape that doesn't have a service_id
    # yet — a brand-new dedicated datastore being created (Task 11). Mirrors
    # ResizeService's checks without the "already exists" bookkeeping.
    def self.check_new_shape(team:, server:, shape:)
      return disabled unless Wokku.config.resource_builder?
      return Result.new(ok: false, error: shape.errors.join(", ")) unless shape.valid?
      before = team_allocations(team)
      after = before + [ { shape: shape, instances: 1 } ]
      unless Wokku.config.plan_enforcer.allowed?(team, :resources, from: before, to: after)
        return Result.new(ok: false, error: "That size is over your account limit — pay your first invoice to go higher.")
      end
      CapacityGuard.check!(server, add_mb: shape.memory_mb)
      Result.new(ok: true)
    rescue CapacityGuard::Full => e
      notify_capacity_full(server)
      Result.new(ok: false, error: e.message)
    end

    def initialize(app:, user:, processes:, volume_disk_gb: nil)
      @app, @user = app, user
      @raw_processes = processes
      @volume_disk_gb = volume_disk_gb
    end

    def call
      return self.class.disabled unless Wokku.config.resource_builder?
      @processes = normalize(@raw_processes)
      shapes = @processes.to_h do |proc, p|
        next [ proc, :sleeping ] if ActiveModel::Type::Boolean.new.cast(p[:sleeping])
        shape = Shape.new(cpu: p[:cpu], memory_mb: p[:memory_mb])
        raise Rejected, "#{proc}: #{shape.errors.join(', ')}" unless shape.valid?
        [ proc, shape ]
      end
      counts = @processes.transform_values { |p| Integer(p.fetch(:count, 1).to_s, exception: false) }
      raise Rejected, "Instance count must be 0–10" unless counts.values.all? { |c| c&.between?(0, 10) }
      raise Rejected, "Use Stop to stop the app — web can't be scaled to 0 here." if counts["web"]&.zero?
      if shapes.any? { |proc, s| s == :sleeping && counts[proc] > 1 }
        raise Rejected, "Free sleeping apps run a single instance."
      end

      disk = @volume_disk_gb.nil? ? nil : Integer(@volume_disk_gb.to_s, exception: false)
      raise Rejected, "Disk must be 0–100 GB" if !@volume_disk_gb.nil? && !disk&.between?(0, 100)

      check_sleeping_quota!(shapes)

      before = self.class.team_allocations(@app.team)
      before_mb = CapacityGuard.reserved_mb(@app.server)
      ActiveRecord::Base.transaction do
        persist!(shapes, counts, disk)
        after = self.class.team_allocations(@app.team)
        unless Wokku.config.plan_enforcer.allowed?(@app.team, :resources, from: before, to: after)
          raise Rejected, "That size is over your account limit — pay your first invoice to go higher."
        end
        CapacityGuard.check_change!(@app.server, before_mb: before_mb)
      end
      # Not-yet-deployed apps get their shape on first deploy's converge.
      if shapes.any? && !@app.created?
        @app.update(pending_action: "resize")
        ApplyResourcesJob.perform_later(@app.id)
      end
      Result.new(ok: true)
    rescue CapacityGuard::Full => e
      self.class.notify_capacity_full(@app.server)
      Result.new(ok: false, error: e.message)
    rescue Rejected, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
      Result.new(ok: false, error: e.message)
    end

    private

    def normalize(processes)
      processes = processes.to_unsafe_h if processes.respond_to?(:to_unsafe_h)
      raise Rejected, "processes must be an object" unless processes.is_a?(Hash)
      processes.to_h do |proc, p|
        p = p.to_unsafe_h if p.respond_to?(:to_unsafe_h)
        raise Rejected, "#{proc}: must be an object" unless p.is_a?(Hash)
        [ proc.to_s, p.symbolize_keys ]
      end
    end

    # Free sleeping quota (fix round 1 #2). Builder-mode create/resize skips
    # enforce_plan_quota!, and a sleeping allocation has no shape, so
    # team_allocations (the plan_enforcer :resources view) never sees it —
    # without this, a builder user could mint unlimited free sleeping apps.
    # Counts the same way PlanEnforceable#current_box_count does
    # (dyno_tier&.size_key == "sleeping") so this agrees with the legacy
    # box-picker's own enforcement instead of drifting from it. `.to_f`
    # comparison: quota may be Float::INFINITY (OSS null enforcer).
    def check_sleeping_quota!(shapes)
      new_sleeping = shapes.count do |proc, s|
        next false unless s == :sleeping
        existing = @app.dyno_allocations.find_by(process_type: proc)
        !(existing && existing.dyno_tier&.size_key == "sleeping")
      end
      return if new_sleeping.zero?

      quota = Wokku.config.plan_enforcer.quota(@user, :box, "sleeping").to_f
      current = @user.teams.flat_map(&:app_records).flat_map(&:dyno_allocations)
                     .select { |a| a.dyno_tier&.size_key == "sleeping" }.sum(&:count)
      return if current + new_sleeping <= quota

      raise Rejected, "You can have #{quota.to_i} free sleeping apps — pick a paid size."
    end

    def persist!(shapes, counts, disk)
      shapes.each do |proc, shape|
        alloc = @app.dyno_allocations.find_or_initialize_by(process_type: proc)
        if shape == :sleeping
          alloc.assign_attributes(dyno_tier: DynoTier.find_by!(name: "free"), cpu: nil, memory_mb: nil)
        else
          alloc.assign_attributes(dyno_tier: nil, cpu: shape.cpu, memory_mb: shape.memory_mb)
        end
        alloc.count = counts[proc]
        alloc.save!
        @app.process_scales.find_or_initialize_by(process_type: proc).update!(count: counts[proc])
      end
      @app.update!(volume_disk_gb: disk) unless disk.nil?
    end
  end
end
