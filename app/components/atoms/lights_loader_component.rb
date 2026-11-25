module Atoms
  # The Lights logo as a loading indicator: seven squares on the 5x3 logo grid
  # lighting in path order (positions + timing live in wokku.css, .wk-lights).
  class LightsLoaderComponent < ApplicationComponent
    SIZES = { sm: "wk-lights-sm", md: "wk-lights-md", lg: "wk-lights-lg" }.freeze

    def initialize(size: :md, label: nil, decorative: false)
      @decorative = decorative
      @size = SIZES.fetch(size)
      @label = label
    end

    attr_reader :decorative

    def aria_label = @label.presence || t("loading.default")
    def css_class = "wk-lights #{@size}"
  end
end
