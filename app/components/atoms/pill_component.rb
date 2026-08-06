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

    def initialize(dot: :accent, **opts)
      @dot = dot
      @opts = opts
    end

    def container_classes
      cx(
        "inline-flex items-center gap-2 px-3.5 py-1.5 bg-paper border-1.5 border-ink rounded-full font-sans text-sm text-ink font-medium tracking-tight",
        @opts[:class]
      )
    end

    def dot_classes
      cx("inline-block w-2 h-2 rounded-full", DOTS[@dot])
    end
  end
end
