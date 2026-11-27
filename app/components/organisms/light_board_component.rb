module Organisms
  # Canvas light board (fleet mode; text mode = 5x7 dot-matrix of a name; story
  # mode = the landing's PUSH -> BUILD -> LIVE sequence). The canvas is decorative;
  # `label` is the screen-reader summary. Fleet: data-light-board-data-value is the
  # JSON of Apps::Fleet.for(apps) entries. Story: `data` = { steps:, status_labels:,
  # repo: } (all optional, localized by the caller).
  class LightBoardComponent < ApplicationComponent
    MODES = %i[fleet text story].freeze
    STORY_DEFAULTS = {
      steps: %w[PUSH BUILD LIVE],
      status_labels: { push: "receiving · git push", build: "building · {pct}%", live: "live · toko-kopi.wokku.app" },
      repo: "toko-kopi · main@4f2a91c"
    }.freeze

    def initialize(data: {}, label:, mode: :fleet)
      @mode = mode.to_sym
      raise ArgumentError, "unknown light board mode: #{mode.inspect}" unless MODES.include?(@mode)
      @data = @mode == :story ? STORY_DEFAULTS.merge((data || {}).to_h.symbolize_keys) : data
      @label = label
    end

    attr_reader :mode, :data, :label

    def story_status
      data[:status_labels].to_h.symbolize_keys.fetch(:live, STORY_DEFAULTS[:status_labels][:live])
    end

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
