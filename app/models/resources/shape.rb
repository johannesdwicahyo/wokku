module Resources
  # A CPU/RAM/disk allocation on the builder's slider grid (spec 2026-09-24).
  # Pure value object: validation, grid snapping, presets. No prices — the
  # engine asks Wokku.config.pricing for those.
  class Shape
    GRID = {
      cpu:       { min: 0.25, max: 4.0,  step: 0.25 },
      memory_mb: { min: 256,  max: 8192, step: 256 },
      disk_gb:   { min: 0,    max: 100,  step: 1 }
    }.freeze

    PRESETS = {
      "nano"     => { cpu: 0.25, memory_mb: 256 },
      "starter"  => { cpu: 0.25, memory_mb: 512 },
      "standard" => { cpu: 0.5,  memory_mb: 1024 },
      "large"    => { cpu: 1.0,  memory_mb: 2048 },
      "x-large"  => { cpu: 2.0,  memory_mb: 4096 }
    }.freeze

    sql_presets = {
      "small"  => { cpu: 0.25, memory_mb: 512,  disk_gb: 5 },
      "medium" => { cpu: 0.5,  memory_mb: 1024, disk_gb: 20 },
      "large"  => { cpu: 1.0,  memory_mb: 2048, disk_gb: 50 }
    }.freeze
    SERVICE_PRESETS = {
      "postgres" => sql_presets, "mariadb" => sql_presets, "mongodb" => sql_presets,
      "redis" => {
        "small"  => { cpu: 0.25, memory_mb: 256,  disk_gb: 1 },
        "medium" => { cpu: 0.25, memory_mb: 1024, disk_gb: 2 },
        "large"  => { cpu: 0.5,  memory_mb: 2048, disk_gb: 4 }
      }
    }.freeze

    attr_reader :cpu, :memory_mb, :disk_gb

    def self.round_up(cpu:, memory_mb:, disk_gb: 0)
      new(cpu: snap_up(cpu, :cpu), memory_mb: snap_up(memory_mb, :memory_mb).to_i, disk_gb: snap_up(disk_gb, :disk_gb).to_i)
    end

    def self.snap_up(value, key)
      g = GRID.fetch(key)
      ((value.to_f / g[:step]).ceil * g[:step]).clamp(g[:min], g[:max])
    end

    def self.whole(v)
      f = Float(v, exception: false)
      f && f == f.floor ? f.to_i : nil
    end

    def initialize(cpu:, memory_mb:, disk_gb: 0)
      @cpu       = Float(cpu, exception: false)
      @memory_mb = self.class.whole(memory_mb)
      # If disk_gb is explicitly nil or 0, it defaults to 0. Otherwise coerce
      # via whole(), which returns nil for non-whole values (error).
      @disk_gb   = disk_gb.nil? || disk_gb == 0 ? 0 : self.class.whole(disk_gb)
    end

    # mongod's WiredTiger cache floor is 256 MB and the image's first-boot
    # init runs mongosh beside it; at 128 MB init is OOM-killed before the
    # root user exists (prod smoke 2026-10-07). wokkud clamps to the same
    # floor (dedicatedEngineSpec.minMemoryMB) for legacy-tier paths.
    ENGINE_MIN_MEMORY_MB = { "mongodb" => 512 }.freeze

    def errors(engine: nil)
      grid = GRID.filter_map do |key, g|
        v = public_send(key)
        next if v && v.between?(g[:min], g[:max]) && (v / g[:step].to_f % 1).zero?
        "#{key.to_s.tr('_', ' ').sub('mb', '(MB)').sub('gb', '(GB)').sub('cpu', 'CPU')} must be #{g[:min]}–#{g[:max]} in steps of #{g[:step]}"
      end
      floor = ENGINE_MIN_MEMORY_MB[engine.to_s]
      grid << "#{engine} needs at least #{floor} MB memory" if floor && memory_mb && memory_mb < floor
      grid
    end

    def valid?(engine: nil) = errors(engine: engine).empty?
    def to_h = { cpu: cpu, memory_mb: memory_mb, disk_gb: disk_gb }
    def ==(other) = other.is_a?(Shape) && to_h == other.to_h
    alias eql? ==
    def hash = to_h.hash
  end
end
