module Molecules
  class WhyCardComponent < ApplicationComponent
    DOT_TONES = { hot: "bg-hot", accent: "bg-accent", success: "bg-success", ink: "bg-ink" }.freeze

    def initialize(num:, tag:, title:, body:, dot: :accent, position:)
      @num = num
      @tag = tag
      @title = title
      @body = body
      @dot = dot
      @position = position
    end
    attr_reader :num, :tag, :title, :body, :position

    def dot_class; DOT_TONES[@dot]; end

    def border_classes
      c = []
      c << "border-r-1.5 border-ink" unless @position[:last_col]
      c << "border-b-1.5 border-ink" unless @position[:last_row]
      c.join(" ")
    end
  end
end
