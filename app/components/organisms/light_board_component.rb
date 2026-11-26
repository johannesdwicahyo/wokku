module Organisms
  # Canvas light board (Phase 3: fleet mode only). The canvas is decorative;
  # `label` is the screen-reader summary. data-light-board-data-value is the
  # JSON of Apps::Fleet.for(apps) entries; the controller reads each `states`.
  class LightBoardComponent < ApplicationComponent
    def initialize(data:, label:, mode: :fleet)
      @mode = mode
      @data = data
      @label = label
    end

    attr_reader :mode, :data, :label

    # "6 processes: 5 running, 1 deploying" ("" when the fleet is empty).
    def self.fleet_label(counts)
      total = counts.values.sum
      return "" if total.zero?
      parts = Apps::Fleet::STATES.filter_map do |s|
        "#{counts[s]} #{I18n.t("apps.fleet.state.#{s}")}" if counts[s].to_i.positive?
      end
      I18n.t("apps.fleet.summary", count: total, parts: parts.join(", "))
    end
  end
end
