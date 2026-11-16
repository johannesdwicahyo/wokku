module Molecules
  class AppsStatusStripComponent < ApplicationComponent
    def initialize(apps:, plan:, box_usage:)
      @apps = apps
      @plan = plan
      @box_usage = box_usage
    end
    attr_reader :apps, :plan, :box_usage

    def state_counts
      @apps.group_by { |a| a.status.to_s }.transform_values(&:count)
    end

    # Only apps actually building. :created also covers apps whose deploys
    # all failed — counting those as "building" hid the failure.
    def in_progress_count
      state_counts["deploying"].to_i
    end

    def total_boxes_used
      box_usage.values.sum
    end

    def total_boxes_allowed
      # Include sleeping — total_boxes_used counts every size (incl. sleeping),
      # so the allowance must too, else a Pro user reads "8 / 5" instead of
      # "8 / 8" (3 sleeping + 3 small + 2 medium).
      %w[sleeping small medium large xlarge].sum { |s| plan.quota_for(s) }
    end

    # Per-size composition of the boxes in use, e.g. [["sleeping", 3],
    # ["medium", 2]] — only sizes with at least one box, in ascending order.
    # Keyed by the canonical box vocabulary (translated from the DynoTier
    # name), NOT DynoTier#size_key (which is mis-bucketed). Sums to
    # total_boxes_used.
    def box_breakdown
      counts = Hash.new(0)
      apps.each do |app|
        app.dyno_allocations.each do |alloc|
          size = DynoTier::DYNO_TIER_TO_BOX_SIZE[alloc.dyno_tier&.name]
          counts[size] += alloc.count if size
        end
      end

      DynoTier::BOX_SIZE_TO_DYNO_TIER.keys.filter_map do |size|
        [ size, counts[size], plan.quota_for(size) ] if counts[size].positive?
      end
    end
  end
end
