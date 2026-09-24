# frozen_string_literal: true

module Organisms
  # Slider builder for one resource (spec 2026-09-24 §5). Presets only
  # pre-fill; the sliders are the source of truth. Prices come from the
  # pricing seam and are hidden on OSS.
  class ResourceBuilderComponent < ApplicationComponent
    def initialize(name:, shape:, presets:, instances: nil, disk: false, sleeping_option: false,
                   sleeping: false, min_disk_gb: 0, rails_hint: false)
      @name, @shape, @presets, @instances = name, shape, presets, instances
      @disk, @sleeping_option, @sleeping = disk, sleeping_option, sleeping
      @min_disk_gb, @rails_hint = min_disk_gb, rails_hint
    end
    attr_reader :shape, :presets, :instances, :sleeping, :min_disk_gb, :rails_hint

    def disk? = @disk
    def sleeping_option? = @sleeping_option
    def field(key) = @name.present? ? "#{@name}[#{key}]" : key.to_s
    def grid(key) = Resources::Shape::GRID.fetch(key)
    def units = Wokku.config.pricing.unit_prices
    def price_idr = Wokku.config.pricing.monthly_idr(shape, instances: instances || 1)

    def idr(n) = "Rp#{n.to_i.to_s.reverse.scan(/\d{1,3}/).join('.').reverse}"
    def mem_label(mb) = mb >= 1024 ? "#{(mb / 1024.0).to_s.delete_suffix('.0')} GB" : "#{mb} MB"
  end
end
