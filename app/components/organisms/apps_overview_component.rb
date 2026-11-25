module Organisms
  # Overview panel: fleet light board + Running readout + host-injected readouts
  # (Wokku.config.apps_index_readouts; none on self-host).
  class AppsOverviewComponent < ApplicationComponent
    def initialize(fleet:, running:, total:, deploying:, readouts: [])
      @fleet = fleet
      @running = running
      @total = total
      @deploying = deploying
      @readouts = readouts
    end

    attr_reader :fleet, :running, :total, :deploying, :readouts

    def board_label = Organisms::LightBoardComponent.fleet_label(Apps::Fleet.counts(fleet))

    # Calls the seam; never raises. Drops entries that aren't hashes with label and value.
    def self.readouts_for(view, team)
      list = Wokku.config.apps_index_readouts.call(view, team)
      Array.wrap(list).select { |r| r.is_a?(Hash) && r[:label].present? && r[:value].present? }
    rescue StandardError => e
      Rails.logger.error("apps_index_readouts failed: #{e.class}: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
      []
    end
  end
end
