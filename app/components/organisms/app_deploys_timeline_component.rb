# frozen_string_literal: true

module Organisms
  # Newest releases on the app overview side column: Live / Failed tags,
  # Roll back for older recorded artifacts, Log for failures.
  class AppDeploysTimelineComponent < ApplicationComponent
    include TimeAgoHelper
    MAX = 4

    def initialize(app:, releases:, current_release:, can_update:)
      @app, @releases, @current, @can_update = app, releases.to_a.first(MAX), current_release, can_update
    end
    attr_reader :app, :releases

    def current?(r) = r == @current
    def failed?(r) = r.deploy&.failed? || r.deploy&.timed_out?
    def can_roll_back?(r)
      @can_update && !current?(r) && r.deploy&.succeeded? && RollbackArtifactResolver.recorded?(r.deploy)
    end

    def meta(r)
      d = r.deploy
      secs = d&.duration
      [ d&.description.presence || d&.commit_sha&.first(7),
        time_ago(r.created_at),
        (t("apps.timeline.duration", seconds: secs.round) if secs) ].compact.join(" · ")
    end
  end
end
