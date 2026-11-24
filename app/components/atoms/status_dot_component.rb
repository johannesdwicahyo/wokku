module Atoms
  class StatusDotComponent < ApplicationComponent
    STATES = {
      live:     { light: :running,   color: "text-live",   label: "[live]" },
      building: { light: :deploying, color: "text-ink",    label: "[building]" },
      crashed:  { light: :crashed,   color: "text-bad-text", label: "[crashed]" },
      sleeping: { light: :sleeping,  color: "text-dim",    label: "[sleeping]" },
      ok:       { light: :healthy,   color: "text-live",   label: nil }
    }.freeze

    def initialize(state: :live, label: nil)
      @state = STATES[state] || STATES[:live]
      @label_override = label
    end

    def light = @state[:light]
    def text_classes = "text-[11px] font-medium #{@state[:color]}"
    def label = @label_override || @state[:label]
  end
end
