module Atoms
  class StatusDotComponent < ApplicationComponent
    STATES = {
      live:     { dot: "bg-success", color: "text-success", label: "[live]" },
      building: { dot: "bg-warn",    color: "text-warn",    label: "[building]" },
      crashed:  { dot: "bg-danger",  color: "text-danger",  label: "[crashed]" },
      sleeping: { dot: "bg-dim",     color: "text-dim",     label: "[sleeping]" },
      ok:       { dot: "bg-success", color: "text-success", label: nil },
    }.freeze

    def initialize(state: :live, label: nil)
      @state = STATES[state] || STATES[:live]
      @label_override = label
    end

    def dot_classes;  "inline-block w-1.5 h-1.5 #{@state[:dot]}"; end
    def text_classes; "font-mono text-[11px] #{@state[:color]} tracking-tight"; end
    def label;        @label_override || @state[:label]; end
  end
end
