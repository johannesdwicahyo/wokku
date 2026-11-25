module Atoms
  # Tiny CPU-style bar sparkline; nil = no sample. Heights scale to `max` (18 px).
  class LightBarsComponent < ApplicationComponent
    def initialize(values:, label:, max: 100)
      @values = values
      @label = label
      @max = max
    end

    attr_reader :values, :label

    def empty? = values.blank? || values.all?(&:nil?)
    def height(v) = [ 2, [ v.to_i, @max ].min * 18 / @max ].max
    def bar_class(v) = v.to_i.positive? ? "on bg-live" : "bg-dim"
  end
end
