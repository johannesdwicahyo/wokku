module Organisms
  class WhyComponent < ApplicationComponent
    DOTS = [:hot, :accent, :success, :success].freeze

    def items
      t('why.items')
    end

    def position_for(i)
      { last_col: i.odd?, last_row: i >= 2 }
    end

    def dot_for(i)
      DOTS[i] || :accent
    end
  end
end
