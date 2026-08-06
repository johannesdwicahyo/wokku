module Molecules
  class StatTileComponent < ApplicationComponent
    TONES = { ink: "text-ink", success: "text-success", danger: "text-danger", warn: "text-warn", accent: "text-accent" }.freeze

    def initialize(label:, value:, sub: nil, tone: :ink, glyph: nil)
      @label = label
      @value = value
      @sub = sub
      @tone = tone
      @glyph = glyph
    end
    attr_reader :label, :value, :sub, :glyph
    def value_class; TONES[@tone]; end
  end
end
