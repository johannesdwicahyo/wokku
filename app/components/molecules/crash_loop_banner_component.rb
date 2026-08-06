module Molecules
  # Shown on the app page when the app is crash-looping (and possibly
  # auto-stopped to break the loop). Tells the user to deploy a fix.
  class CrashLoopBannerComponent < ApplicationComponent
    def initialize(app:)
      @app = app
    end

    def render?
      @app.status.to_s == "crashed"
    end

    attr_reader :app
  end
end
