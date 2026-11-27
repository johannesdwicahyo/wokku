# frozen_string_literal: true

module Organisms
  # App-page Security panel: severity lights from the newest scan of the
  # current image (see ImageScan.for_image). Informational; never says "secure".
  class AppSecurityPanelComponent < ApplicationComponent
    LIGHTS = {
      "critical" => "bg-danger wk-glow-bad",
      "high" => "bg-warn",
      "medium" => "bg-dark-line", "low" => "bg-dark-line", "unknown" => "bg-dark-line"
    }.freeze

    def initialize(app:, scan:)
      @app, @scan = app, scan
    end
    attr_reader :app, :scan

    def counts = scan.counts || {}
    def count(sev) = counts[sev].to_i
    def clean? = LIGHTS.keys.sum { |s| count(s) }.zero?
    def light_class(sev) = cx("wk-light inline-block shrink-0 w-2.5 h-2.5", count(sev).positive? ? LIGHTS[sev] : "bg-dark-line opacity-40")
  end
end
