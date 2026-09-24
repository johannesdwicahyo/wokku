module Molecules
  class DiskUsageBannerComponent < ApplicationComponent
    def initialize(record:)
      @record = record
    end
    def ratio = @ratio ||= Resources::DiskUsage.ratio(@record)
    def render? = ratio && ratio >= DiskUsageWarningJob::THRESHOLD
    def pct = (ratio * 100).round
    def billed_note? = ratio > 1 && Wokku.config.pricing.unit_prices.present?
  end
end
