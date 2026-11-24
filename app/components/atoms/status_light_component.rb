module Atoms
  class StatusLightComponent < ApplicationComponent
    STATES = {
      running:   "bg-live wk-glow-live",
      healthy:   "bg-live wk-glow-live",
      deploying: "bg-ink wk-blink-1s",
      sleeping:  "wk-outline-muted",
      crashed:   "bg-danger wk-glow-bad wk-blink-14s",
      stopped:   "wk-outline-muted",
      created:   "bg-dark-line"
    }.freeze

    def initialize(state:, label: nil, size: 10)
      @state = STATES.key?(state&.to_sym) ? state.to_sym : :created
      @label = label
      @size = size
    end

    attr_reader :state, :label, :size

    def light_classes = cx("wk-light inline-block shrink-0", STATES[state])
    def light_style = "width:#{size}px;height:#{size}px"
    def state_label = t("status_light.#{state}")
  end
end
