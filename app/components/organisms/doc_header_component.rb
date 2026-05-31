module Organisms
  class DocHeaderComponent < ApplicationComponent
    def initialize(eyebrow:, title:, summary: nil, badges: [], edited: nil, source: "#")
      @eyebrow = eyebrow
      @title   = title
      @summary = summary
      @badges  = badges
      @edited  = edited
      @source  = source
    end
    attr_reader :eyebrow, :title, :summary, :badges, :edited, :source
  end
end
