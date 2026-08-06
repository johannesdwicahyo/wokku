module Molecules
  class RecentActivityCardComponent < ApplicationComponent
    def initialize(events:, limit: 10)
      @events = (events || []).first(limit)
    end
    attr_reader :events

    def empty?
      events.empty?
    end
  end
end
