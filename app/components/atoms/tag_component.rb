module Atoms
  class TagComponent < ApplicationComponent
    TONES = {
      ink:     "border-ink text-ink",
      dim:     "border-rule-soft text-dim",
      accent:  "border-accent text-accent",
      hot:     "border-hot text-hot",
      success: "border-success text-success",
      warn:    "border-warn text-warn",
      danger:  "border-danger text-danger",
    }.freeze

    def initialize(tone: :dim, **opts)
      @tone = tone
      @opts = opts
    end

    def classes
      cx(
        "inline-flex items-center gap-1.5 px-2 py-0.5 border font-mono text-[10px] font-semibold uppercase tracking-widest whitespace-nowrap",
        TONES[@tone],
        @opts[:class]
      )
    end
  end
end
