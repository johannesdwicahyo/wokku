module Resources
  # RAM admission control for one host (spec 2026-09-24 §6). CPU is allowed
  # to overcommit (limits are ceilings on a shared box); RAM is not.
  # ponytail: sums DB rows per check — fine at one-host scale; cache per
  # server if placement ever spans many hosts.
  module CapacityGuard
    Full = Class.new(StandardError)
    HEADROOM = 0.9

    module_function

    def reserved_mb(server)
      apps = server.app_records.includes(:process_scales, dyno_allocations: :dyno_tier)
      app_mb = apps.sum do |app|
        scales = app.process_scales.index_by(&:process_type)
        app.dyno_allocations.reject(&:sleeping?).sum do |a|
          count = scales[a.process_type]&.count
          count = 1 if count.nil? && a.process_type == "web"
          a.effective_memory_mb.to_i * count.to_i
        end
      end
      svc_mb = server.database_services.where(shared: false).sum do |db|
        db.memory_mb || db.service_tier&.spec&.dig("memory_mb").to_i
      end
      app_mb + svc_mb
    end

    def check!(server, add_mb:)
      total = server.vitals&.dig("mem_total_mb").to_i
      return if total.zero? || add_mb <= 0
      return if reserved_mb(server) + add_mb <= total * HEADROOM
      OpsMailer.capacity_full(server).deliver_later
      raise Full, "Server capacity is full — try a smaller size."
    end
  end
end
