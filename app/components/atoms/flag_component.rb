module Atoms
  class FlagComponent < ApplicationComponent
    SIZES = {
      xs: { w: 18,  band: 6 },
      sm: { w: 22,  band: 7 },
      md: { w: 28,  band: 9 },
      lg: { w: 36,  band: 12 }
    }.freeze

    def initialize(size: :sm)
      @s = SIZES[size]
    end

    def width; @s[:w]; end
    def band;  @s[:band]; end
  end
end
