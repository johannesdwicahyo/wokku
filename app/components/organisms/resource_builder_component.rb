# frozen_string_literal: true

module Organisms
  # Slider builder for one resource (spec 2026-09-24 §5). Presets only
  # pre-fill; the sliders are the source of truth. Prices come from the
  # pricing seam and are hidden on OSS.
  class ResourceBuilderComponent < ApplicationComponent
    def initialize(name:, shape:, presets:, instances: nil, disk: false, sleeping_option: false,
                   sleeping: false, min_disk_gb: 0, rails_hint: false, kind: :app)
      @name, @shape, @presets, @instances = name, shape, presets, instances
      @disk, @sleeping_option, @sleeping = disk, sleeping_option, sleeping
      @min_disk_gb, @rails_hint = min_disk_gb, rails_hint
      @kind = kind
    end
    attr_reader :shape, :presets, :instances, :sleeping, :min_disk_gb, :rails_hint

    def disk? = @disk
    def sleeping_option? = @sleeping_option
    def field(key) = @name.present? ? "#{@name}[#{key}]" : key.to_s
    def grid(key) = Resources::Shape::GRID.fetch(key)
    def units = Wokku.config.pricing.unit_prices(**kind_opts(:unit_prices))
    def price_idr = Wokku.config.pricing.monthly_idr(shape, instances: instances || 1, **kind_opts(:monthly_idr))

    # Optional seam method (older/custom providers may lack it → nothing shown).
    def upcoming_change
      pricing = Wokku.config.pricing
      pricing.upcoming_change(**kind_opts(:upcoming_change)) if pricing.respond_to?(:upcoming_change)
    end

    # `kind:` is only passed when kind is non-default AND the provider's
    # method accepts it (older host providers predate it). Doubles/mocks
    # with a rest signature count as accepting.
    def kind_opts(meth)
      return {} if @kind == :app
      params = Wokku.config.pricing.method(meth).parameters
      accepts = params.any? { |t, n| (t == :key || t == :keyreq) && n == :kind } || params.any? { |t, _| t == :keyrest }
      accepts ? { kind: @kind } : {}
    end

    UNIT_LABELS = { "cpu" => "vCPU", "memory_gb" => "RAM GB", "disk_gb" => "disk GB" }.freeze

    def upcoming_change_text(change)
      parts = UNIT_LABELS.filter_map do |key, label|
        from, to = change[:from][key], change[:to][key]
        "#{label} #{idr(from)} → #{idr(to)}" unless from == to
      end
      t("resources.price_change", date: l(change[:effective_on], format: "%-d %b %Y"), changes: parts.join(" · "),
        default: "Prices change on %{date}: %{changes} (per month).")
    end

    def idr(n) = "Rp#{n.to_i.to_s.reverse.scan(/\d{1,3}/).join('.').reverse}"
    def mem_label(mb) = mb >= 1024 ? "#{(mb / 1024.0).to_s.delete_suffix('.0')} GB" : "#{mb} MB"

    # A chip is pressed only when cpu+memory match AND, when this preset
    # carries a disk_gb (datastore presets), the current disk matches too —
    # otherwise moving only the disk slider would leave a stale chip lit.
    def preset_pressed?(p)
      !sleeping && shape.cpu == p[:cpu] && shape.memory_mb == p[:memory_mb] &&
        (p[:disk_gb].nil? || !disk? || p[:disk_gb] == shape.disk_gb)
    end
  end
end
