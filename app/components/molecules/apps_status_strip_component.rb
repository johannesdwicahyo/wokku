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

    def in_progress_count
      state_counts["deploying"].to_i + state_counts["created"].to_i
    end

    def total_boxes_used
      box_usage.values.sum
    end

    def total_boxes_allowed
      %w[small medium large xlarge].sum { |s| plan.quota_for(s) }
    end
  end
end
