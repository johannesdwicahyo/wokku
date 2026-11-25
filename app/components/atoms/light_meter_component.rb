module Atoms
  class LightMeterComponent < ApplicationComponent
    TONES = { ink: "bg-ink", live: "bg-live" }.freeze

    def initialize(total:, on:, label:, tone: :ink)
      @total = total
      @on = on.clamp(0, total)
      @label = label
      @tone = tone
    end

    attr_reader :total, :on, :label

    def lit_class = TONES.fetch(@tone, TONES[:ink])
    def square_class(i) = i < on ? "on #{lit_class}" : ""
  end
end
