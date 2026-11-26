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
    # Same desired/running numbers as the processes rack (AppProcessesComponent);
    # apps with no allocations fall back to the app-status fleet.
    def rack = (@rack ||= Organisms::AppProcessesComponent.new(app: app, can_update: false))

    def fleet
      @fleet ||= if app.dyno_allocations.to_a.empty?
        Apps::Fleet.for([ app ])
      else
        idle = %i[stopped crashed sleeping created].include?(app.status&.to_sym) ? app.status.to_sym : :deploying
        states = rack.allocations.flat_map do |a|
          up = [ rack.running_for(a.process_type), rack.desired(a) ].min
          Array.new(up, :running) + Array.new(rack.desired(a) - up, idle)
        end
        [ { app_id: app.id, name: app.name, states: states.presence || [ :stopped ] } ]
      end
    end
    def count = Apps::Fleet.counts(fleet)[:running].to_i
    def board_label = Organisms::LightBoardComponent.fleet_label(Apps::Fleet.counts(fleet))

    def release_value = @release ? "v#{@release.version}" : none

    def release_sub
      at = @release&.deploy&.finished_at
      t("apps.detail.board.live_for", duration: helpers.distance_of_time_in_words(at, Time.current)) if at
    end

    def p95 = stats[:p95_ms] && "#{stats[:p95_ms].round} ms"

    def err_pct = stats[:err_5xx_pct] && "#{helpers.number_with_precision(stats[:err_5xx_pct], precision: 2, strip_insignificant_zeros: true)} %"

    def err_sub
      return unless stats[:err_5xx_pct]
      t("apps.detail.board.errors_sub", err: delimit(stats[:err_5xx_hour]), req: delimit(stats[:req_hour]))
    end

    def delimit(n) = helpers.number_with_delimiter(n.to_i)
  end
end
