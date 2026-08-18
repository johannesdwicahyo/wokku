module Molecules
  class DashedCalloutComponent < ApplicationComponent
    TONES = { ink: "text-ink", accent: "text-accent" }.freeze

    def initialize(tone: :ink, position: {}, width: nil)
      @tone = tone
      @position = position
      @width = width
    end

    def classes
      cx("absolute border border-line bg-bg rounded-lg p-3 text-[11px] tracking-tight pointer-events-none", TONES[@tone])
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
