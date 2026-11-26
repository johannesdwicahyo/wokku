# frozen_string_literal: true

module Organisms
  # Apps overview: the newest in-progress deploy as a four-stage track with
  # its live log (DeployChannel). No build percentage: wokkud reports none.
  class DeployTrackComponent < ApplicationComponent
    STAGES = %i[push build release live].freeze
    LOG_LINES = 12

    def initialize(deploy:, more: 0)
      @deploy = deploy
      @more = more.to_i
    end

    attr_reader :deploy, :more

    def render? = deploy.present?

    def app = deploy.app_record

    def next_version
      v = deploy.release&.version || app.releases.maximum(:version)&.+(1)
      v ? "v#{v}" : "—"
    end

    # Push is done once the deploy exists; Build runs while the deploy is
    # open; Release/Live complete when the list frame reloads on finish.
    def stage_state(stage)
      { push: :done, build: :run }.fetch(stage, :pending)
    end

    def sub_line
      sha = deploy.commit_sha.to_s.first(7).presence
      started = t("apps.deploy_track.started", ago: time_ago(deploy.started_at || deploy.created_at))
      [ sha, started ].compact.join(" · ")
    end

    def log_tail
      deploy.log.to_s.lines.last(LOG_LINES).join
    end
  end
end
