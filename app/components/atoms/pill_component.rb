module Atoms
  class PillComponent < ApplicationComponent
    DOTS = {
      accent:  "bg-accent",
      hot:     "bg-hot",
      success: "bg-success",
      warn:    "bg-warn",
      danger:  "bg-danger",
      ink:     "bg-ink"
    }.freeze

    TINTS = {
      accent:  "bg-accent-soft text-accent",
      hot:     "bg-hot-soft text-hot",
      success: "bg-success-soft text-success",
      warn:    "bg-warn-soft text-warn",
      danger:  "bg-danger-soft text-danger",
      ink:     "bg-bg-deep text-ink-soft"
    }.freeze

    def initialize(dot: :accent, **opts)
      @dot = dot
      @opts = opts
    end

    def container_classes
      cx(
        "inline-flex items-center gap-2 px-2 py-0.5 rounded text-[11px] font-medium",
        TINTS[@dot],
        @opts[:class]
      )
    end

    def dot_classes
      cx("inline-block w-2 h-2 rounded-full", DOTS[@dot])
    end
  end
end
