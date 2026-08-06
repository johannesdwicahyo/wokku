# frozen_string_literal: true

module Molecules
  # Brutalist loading skeleton shown inside a lazy turbo-frame until its
  # real content arrives. Variant picks a shape that roughly matches the
  # section it stands in, to minimize layout shift on swap.
  class SkeletonComponent < ApplicationComponent
    VARIANTS = %i[table tiles card chart text].freeze

    def initialize(variant: :card, rows: 3, cols: 3)
      @variant = VARIANTS.include?(variant.to_sym) ? variant.to_sym : :card
      @rows    = rows
      @cols    = cols
    end

    attr_reader :variant, :rows, :cols

    # Pulsing bar; motion-safe so prefers-reduced-motion users get a
    # static placeholder.
    def bar(extra = "")
      "bg-bg-deep border border-rule-soft motion-safe:animate-pulse #{extra}"
    end
  end
end
