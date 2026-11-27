module Organisms
  # Landing hero: perspective field of server lights with the floating Wokku
  # mark (Canvas 2D, light-field Stimulus controller). Decorative-but-labelled
  # canvas; the CSS poster shows before the first draw / without JS.
  class LightFieldComponent < ApplicationComponent
    DENSITIES = %i[normal low].freeze

    def initialize(label:, logo: true, density: :normal)
      @label = label
      @logo = logo
      @density = density.to_sym
      raise ArgumentError, "unknown density: #{density.inspect}" unless DENSITIES.include?(@density)
    end

    attr_reader :label, :logo, :density
  end
end
