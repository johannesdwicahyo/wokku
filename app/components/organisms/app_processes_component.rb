# frozen_string_literal: true

module Organisms
  # Processes rack on the app overview: one row per process type with live
  # state from the heartbeat (no SSH) and ± scaling that returns to the overview.
  class AppProcessesComponent < ApplicationComponent
    include ApplicationHelper

    # {process_type => running task count} from heartbeat live_containers.
    def self.running_counts(app)
      Array(app.live_containers).select { |c| c["process"].present? && c["state"].to_s == "running" }
                                .group_by { |c| c["process"] }.transform_values(&:size)
    end

    def initialize(app:, can_update:)
      @app = app
      @can_update = can_update
    end

    attr_reader :app

    def can_update? = @can_update

    def allocations
      @allocations ||= app.dyno_allocations.includes(:dyno_tier).sort_by { |a| [ a.process_type == "web" ? 0 : 1, a.process_type ] }
    end

    def running = @running ||= self.class.running_counts(app)
    def running_for(type) = running.fetch(type, 0)

    MAX_LIGHTS = 10

    # Desired count, same rule as billing (ApplyChange.team_allocations):
    # the process_scales row, else web 1 / others 0.
    def desired(alloc)
      @scales ||= app.process_scales.index_by(&:process_type)
      @scales[alloc.process_type]&.count || (alloc.process_type == "web" ? 1 : 0)
    end

    def size_label = (allocations.find { |a| a.process_type == "web" } || allocations.first)&.size_label

    def state_for(alloc)
      return :stopped if desired(alloc).zero?
      running_for(alloc.process_type).positive? ? :running : :deploying
    end

    def scale_params(type, count) = { scaling: { type => count }, return_to: "overview" }

    def confirm_for(alloc)
      price = alloc.sleeping? ? nil : Wokku.config.pricing.monthly_idr(shape_for(alloc), instances: 1)
      price ? t("apps.processes.add_confirm_price", type: alloc.process_type, price: idr(price)) : t("apps.processes.add_confirm", type: alloc.process_type)
    end

    def shape_for(alloc)
      @by_type ||= allocations.index_by(&:process_type)
      Resources::ApplyChange.inherited_shape_for(app, alloc.process_type, @by_type)
    end

    # Same Rupiah format as Organisms::ResourceBuilderComponent#idr.
    def idr(n) = "Rp#{n.to_i.to_s.reverse.scan(/\d{1,3}/).join('.').reverse}"
  end
end
