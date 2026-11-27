module Organisms
  # Landing closing wall: dot-matrix board spelling `text` with a pointer ripple
  # (light-wall Stimulus controller). Purely decorative: the real closing copy is
  # HTML laid over it, so the canvas is aria-hidden.
  class LightWallComponent < ApplicationComponent
    def initialize(label: nil, text: "PUSH.")
      @label = label
      @text = text
    end

    attr_reader :label, :text
  end
end
