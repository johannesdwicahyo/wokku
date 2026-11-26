module Organisms
  # One panel, four cells: processes board, release age, p95, 5xx rate. nil -> "—".
  class AppStatusBoardComponent < ApplicationComponent
    def initialize(app:, stats:, current_release:)
      @app = app
      @stats = stats
      @release = current_release
    end

    attr_reader :app, :stats

    def none = t("apps.detail.none")
    def fleet = Apps::Fleet.for([ app ])
    def count = fleet.first[:states].size
    def board_label = Organisms::LightBoardComponent.fleet_label(Apps::Fleet.counts(fleet))

    def release_value = @release ? "v#{@release.version}" : none

    def release_sub
      at = @release&.deploy&.finished_at
      t("apps.detail.board.live_for", duration: helpers.distance_of_time_in_words(at, Time.current)) if at
    end

    def p95 = stats[:p95_ms] && "#{stats[:p95_ms].round} ms"

    def err_pct = stats[:err_5xx_pct] && "#{stats[:err_5xx_pct]} %"

    def err_sub
      return unless stats[:err_5xx_pct]
      t("apps.detail.board.errors_sub", err: delimit(stats[:err_5xx_hour]), req: delimit(stats[:req_hour]))
    end

    def delimit(n) = ActiveSupport::NumberHelper.number_to_delimited(n.to_i, delimiter: t("apps.detail.delimiter"))
  end
end
