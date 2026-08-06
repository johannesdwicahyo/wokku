module Molecules
  # Shows the last few captured CrashEvents on the app page so the most
  # recent crash stays diagnosable (exit code, OOM flag, log excerpt)
  # even after dokku prunes the dead container.
  class RecentCrashesComponent < ApplicationComponent
    def initialize(app:)
      @app = app
    end

    def crashes
      @crashes ||= @app.crash_events.recent.limit(5).to_a
    end

    def render? = crashes.any?

    attr_reader :app
  end
end
