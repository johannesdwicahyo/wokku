# frozen_string_literal: true

module Organisms
  # Size summary + monthly price (price only when the pricing seam has one).
  class AppResourcesPanelComponent < ApplicationComponent
    include RupiahHelper

    def initialize(app:)
      @app = app
    end
    attr_reader :app

    def allocations
      @allocations ||= app.dyno_allocations.includes(:dyno_tier).sort_by { |a| [ a.process_type == "web" ? 0 : 1, a.process_type ] }
    end

    # Same rule as AppProcessesComponent#desired.
    def desired(alloc)
      @scales ||= app.process_scales.index_by(&:process_type)
      @scales[alloc.process_type]&.count || (alloc.process_type == "web" ? 1 : 0)
    end

    def web = allocations.find { |a| a.process_type == "web" } || allocations.first

    def counts = allocations.filter_map { |a| "#{desired(a)} #{a.process_type}" if desired(a).positive? }.join(" + ")

    def size_line
      return unless web
      parts = [ web.size_label ]
      parts << counts if counts.present?
      parts.join(" · ")
    end

    # nil when any allocation has no price (OSS NullPricing).
    def price
      @by_type ||= allocations.index_by(&:process_type)
      prices = allocations.map do |a|
        next 0 if a.sleeping? || desired(a).zero?
        Wokku.config.pricing.monthly_idr(Resources::ApplyChange.inherited_shape_for(app, a.process_type, @by_type), instances: desired(a))
      end
      # Hidden when unpriced (NullPricing) or when nothing is billable (total 0).
      idr(prices.sum) unless prices.any?(&:nil?) || prices.sum.zero?
    end
  end
end
