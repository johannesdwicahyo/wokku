module Atoms
  # Lights logo: seven squares, the middle one live. Variants: :lockup (mark +
  # wordmark), :mark (squares only), :tile (dark rounded square).
  class LogoComponent < ApplicationComponent
    HEIGHTS = { sm: 20, md: 24, lg: 32 }.freeze
    LIVE = "#22C55E".freeze
    SQUARES = [ [ 20, 64 ], [ 196, 64 ], [ 20, 108 ], [ 196, 108 ], [ 64, 152 ], [ 152, 152 ] ].freeze

    def initialize(variant: :lockup, size: :md, href: nil)
      @variant = variant
      @size = HEIGHTS.fetch(size)
      @href = href
    end
    attr_reader :variant, :size, :href
  end
end
