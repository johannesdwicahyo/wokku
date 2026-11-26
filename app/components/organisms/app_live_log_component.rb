# frozen_string_literal: true

module Organisms
  # Live tail: lazy glance frame, polled by live_log_controller.
  class AppLiveLogComponent < ApplicationComponent
    LINES = 50

    def initialize(app:, process_types:)
      @app, @process_types = app, process_types
    end
    attr_reader :app, :process_types

    def src = helpers.dashboard_app_logs_path(app, glance: true, lines: LINES, frame: "app_live_log")
  end
end
