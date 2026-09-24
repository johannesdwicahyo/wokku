module Resources
  # The one write path for per-resource sizing (dashboard, API, create-app).
  # Validates → plan_enforcer :resources → capacity → persist → converge.
  class ApplyChange
    Result = Struct.new(:ok, :error, keyword_init: true)
    Rejected = Class.new(StandardError)

    def self.call(**) = new(**).call

    # Team-wide [{shape:, instances:, service_id:}] for the enforcer's
    # before/after view — shaped processes AND shaped dedicated services.
    def self.team_allocations(team)
      procs = AppRecord.where(team: team).includes(:process_scales, :dyno_allocations).flat_map do |app|
        scales = app.process_scales.index_by(&:process_type)
        app.dyno_allocations.filter_map do |a|
          next unless a.shape
          { shape: a.shape, instances: scales[a.process_type]&.count || (a.process_type == "web" ? 1 : 0) }
        end
      end
      services = DatabaseService.where(shared: false).where.not(cpu: nil)
        .joins(:app_records).where(app_records: { team_id: team.id }).distinct
      procs + services.map { |db| { shape: db.shape, instances: 1, service_id: db.id } }
    end

    def initialize(app:, user:, processes:, volume_disk_gb: nil)
      @app, @user = app, user
      @processes = processes.to_h.transform_keys(&:to_s).transform_values { |v| v.to_h.symbolize_keys }
      @volume_disk_gb = volume_disk_gb
    end

    def call
      shapes = @processes.to_h do |proc, p|
        next [ proc, :sleeping ] if ActiveModel::Type::Boolean.new.cast(p[:sleeping])
        shape = Shape.new(cpu: p[:cpu], memory_mb: p[:memory_mb])
        raise Rejected, "#{proc}: #{shape.errors.join(', ')}" unless shape.valid?
        [ proc, shape ]
      end
      counts = @processes.transform_values { |p| Integer(p.fetch(:count, 1).to_s, exception: false) }
      raise Rejected, "Instance count must be 0–10" unless counts.values.all? { |c| c&.between?(0, 10) }

      disk = @volume_disk_gb.nil? ? nil : Integer(@volume_disk_gb.to_s, exception: false)
      raise Rejected, "Disk must be 0–100 GB" if !@volume_disk_gb.nil? && !disk&.between?(0, 100)

      before = self.class.team_allocations(@app.team)
      ActiveRecord::Base.transaction do
        persist!(shapes, counts, disk)
        after = self.class.team_allocations(@app.team)
        unless Wokku.config.plan_enforcer.allowed?(@app.team, :resources, from: before, to: after)
          raise Rejected, "That size is over your account limit — pay your first invoice to go higher."
        end
        CapacityGuard.check!(@app.server, add_mb: mb(after) - mb(before))
      end
      # Not-yet-deployed apps get their shape on first deploy's converge.
      ApplyResourcesJob.perform_later(@app.id) if shapes.any? && !@app.created?
      Result.new(ok: true)
    rescue Rejected, CapacityGuard::Full => e
      Result.new(ok: false, error: e.message)
    end

    private

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

    def mb(allocs) = allocs.sum { |a| a[:shape].memory_mb * a[:instances] }
  end
end
