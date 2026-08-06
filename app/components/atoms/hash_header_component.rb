module Atoms
  class HashHeaderComponent < ApplicationComponent
    # Responsive: smaller on mobile so long titles don't force the page
    # wide, full size from md up.
    SIZES = {
      sm: "text-2xl md:text-3xl",
      md: "text-3xl md:text-4xl",
      lg: "text-4xl md:text-5xl",
      xl: "text-5xl md:text-6xl"
    }.freeze

    def initialize(title:, kicker: nil, size: :lg)
      @title = title
      @kicker = kicker
      @size = SIZES[size]
    end
    attr_reader :title, :kicker, :size
  end
end
