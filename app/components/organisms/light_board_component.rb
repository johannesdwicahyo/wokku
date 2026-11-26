module Organisms
  # Canvas light board (fleet mode; text mode = 5x7 dot-matrix of a name). The canvas is decorative;
  # `label` is the screen-reader summary. data-light-board-data-value is the
  # JSON of Apps::Fleet.for(apps) entries; the controller reads each `states`.
  class LightBoardComponent < ApplicationComponent
    MODES = %i[fleet text].freeze

    def initialize(data:, label:, mode: :fleet)
      @mode = mode.to_sym
      raise ArgumentError, "unknown light board mode: #{mode.inspect}" unless MODES.include?(@mode)
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
