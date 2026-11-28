module Organisms
  # Landing closing wall: dot-matrix board spelling `text` with a pointer ripple
  # (light-wall Stimulus controller). Purely decorative: the real closing copy is
  # HTML laid over it, so the canvas is aria-hidden.
  class LightWallComponent < ApplicationComponent
    def initialize(text: "PUSH.", logo: false, pulse_form: nil)
      @text = text
      @logo = logo
      @pulse_form = pulse_form
    end

    attr_reader :text, :logo, :pulse_form
  end
end
