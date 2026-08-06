module Molecules
  class DashedCalloutComponent < ApplicationComponent
    TONES = { ink: "border-ink text-ink", accent: "border-accent text-accent" }.freeze

    def initialize(tone: :ink, position: {}, width: nil)
      @tone = tone
      @position = position
      @width = width
    end

    def classes
      cx("absolute border-1.5 border-dashed rounded-lg p-3 font-mono text-[11px] tracking-tight pointer-events-none", TONES[@tone])
    end

    def style
      parts = []
      parts << "width: #{@width}px" if @width
      [ :top, :right, :bottom, :left ].each do |k|
        parts << "#{k}: #{@position[k]}px" if @position[k]
      end
      parts.join("; ")
    end
  end
end
