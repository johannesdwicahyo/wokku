module Organisms
  # Dashboard top bar (desktop breadcrumb + HUD) and phone header (< lg).
  # The clock text is server-rendered; the `clock` Stimulus controller refreshes it.
  class TopBarComponent < ApplicationComponent
    ZONE = "Asia/Jakarta".freeze

    renders_many :actions

    def initialize(crumbs:, page:, region: ENV["WOKKU_REGION"].presence, now: Time.current)
      @crumbs = crumbs
      @page = page
      @region = region
      @now = now
    end
    attr_reader :crumbs, :page, :region

    def clock_text = @now.in_time_zone(ZONE).strftime("%H:%M:%S")
  end
end
