module Resources
  # Resize one dedicated datastore (spec 2026-09-24 §5.3). Disk only grows.
  module ResizeService
    module_function

    def call(db:, user:, shape:)
      return ApplyChange::Result.new(ok: false, error: "Shared add-ons can't be resized") if db.shared?
      return ApplyChange::Result.new(ok: false, error: shape.errors.join(", ")) unless shape.valid?
      if db.disk_gb && shape.disk_gb < db.disk_gb
        return ApplyChange::Result.new(ok: false, error: "Disk can only grow (currently #{db.disk_gb} GB)")
      end
      team = db.app_records.first&.team
      if team
        before = ApplyChange.team_allocations(team)
        after  = before.reject { |a| a[:service_id] == db.id } + [ { shape: shape, instances: 1, service_id: db.id } ]
        unless Wokku.config.plan_enforcer.allowed?(team, :resources, from: before, to: after)
          return ApplyChange::Result.new(ok: false, error: "That size is over your account limit — pay your first invoice to go higher.")
        end
      end
      add_mb = shape.memory_mb - (db.memory_mb || db.service_tier&.spec&.dig("memory_mb").to_i)
      CapacityGuard.check!(db.server, add_mb: add_mb)
      db.update!(cpu: shape.cpu, memory_mb: shape.memory_mb, disk_gb: shape.disk_gb)
      ApplyDatabaseTierJob.perform_later(db.id)
      ApplyChange::Result.new(ok: true)
    rescue CapacityGuard::Full => e
      ApplyChange::Result.new(ok: false, error: e.message)
    end
  end
end
