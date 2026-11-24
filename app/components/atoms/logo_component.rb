module Atoms
  # Lights logo: seven squares, the middle one live. Variants: :lockup (mark +
  # wordmark), :mark (squares only), :tile (dark rounded square).
  class LogoComponent < ApplicationComponent
    HEIGHTS = { sm: 20, md: 24, lg: 32 }.freeze
    LIVE = "#22C55E".freeze
    SQUARES = [ [ 20, 64 ], [ 196, 64 ], [ 20, 108 ], [ 196, 108 ], [ 64, 152 ], [ 152, 152 ] ].freeze

    # Path-order index (TL, ML, B2, live, B4, MR, TR) for each SQUARES entry.
    SEQ = [ 0, 6, 1, 5, 2, 4 ].freeze
    LIVE_SEQ = 3

    def initialize(variant: :lockup, size: :md, href: nil, animated: false, decorative: false)
      @decorative = decorative
      @animated = animated
      @variant = variant
      @size = HEIGHTS.fetch(size)
      @href = href
    end
    attr_reader :variant, :size, :href, :animated, :decorative

    def a11y_attrs = decorative ? 'aria-hidden="true"'.html_safe : 'role="img" aria-label="Wokku"'.html_safe

    # ponytail: only the lights sequence is gated by an ancestor .is-loading (CSS)
    def svg_class = animated ? "wk-logo-anim" : nil
    def seq_style(i) = animated ? "--i:#{i}" : nil
  end
end
