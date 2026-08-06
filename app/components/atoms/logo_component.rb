module Atoms
  class LogoComponent < ApplicationComponent
    SIZES = { sm: 28, md: 36, lg: 48 }.freeze

    def initialize(size: :md, href: nil)
      @size = SIZES[size]
      @href = href
    end
    attr_reader :size, :href
  end
end
