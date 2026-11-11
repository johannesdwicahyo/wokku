module Deploys
  # The build+converge core shared by TarballDeployJob (async generic app
  # deploys) and Preview::Deployer (synchronous per-PR previews). Given an app
  # and a deploy whose `archive_key` is already uploaded, it runs the wokkud
  # build and converges the image, returning the build log. It owns the build
  # Timeout and RAISES on failure: every caller wraps this in its own rescue
  # and writes its own deploy/app status.
  class BuildAndConverge
    # All build/converge failures surface as this one typed error so callers
    # can rescue a single class. Timeout::Error is deliberately NOT wrapped —
    # callers map a timeout to their own distinct status.
    class Error < StandardError; end

    # W7 blocker clearance: there is NO dokku fallback for any app anymore —
    # a fallback build for a Swarm app deploys outside Swarm (split-brain)
    # and parallel builds OOM the host. Sick/unclaimed builder = failed
    # deploy with a clear message, for native and adopted apps alike.
    class BuilderUnavailable < StandardError; end

    DEPLOY_TIMEOUT = 15.minutes # bounds build+converge FROM PICKUP — queue wait is budgeted separately
    CLAIM_WAIT = 35 # seconds of builder-IDLE silence before giving up (sick builder)
    QUEUE_WAIT_MAX = 10.minutes # total claim-wait budget while queued behind live builds
    BUSY_CLAIM_MAX_AGE = 12.minutes # agent build timeout (600s) + slack — older claimed rows are wedged
    POLL = 2

    def self.call(app:, deploy:) = new(app: app, deploy: deploy).call

    def initialize(app:, deploy:)
      @app = app
      @deploy = deploy
    end

    # Returns the build log on success. Raises Timeout::Error on build timeout
    # (callers map to their own timed-out state) or Error for any other
    # build/converge failure.
    def call
      server = @app.server
      unless wokkud_build?(server)
        raise BuilderUnavailable, "wokkud builder unavailable on #{server.name} — deploy cannot proceed"
      end
      @deploy.update!(builder: "wokkud")
      wokkud_build(@app, @deploy, server)
    rescue Timeout::Error
      raise
    rescue ::Lifecycle::Ops::Failed, ::Lifecycle::Ops::Timeout, ::Lifecycle::Ops::Busy, BuilderUnavailable => e
      raise Error, e.message
    end

    private

    def wokkud_build?(server)
      server.wokkud_builds_enabled? && !server.heartbeat_stale? && server.vitals&.dig("registry") == "ok"
    end

    def with_deploy_timeout(&) = Timeout.timeout(DEPLOY_TIMEOUT.to_i, &)

    # Waits for wokkud to claim + finish the build (its output streams into
    # deploy.log via Api::V1::Agent::BuildsController#log while we poll), then
    # converges the pushed image. The claim wait is busy-aware and runs
    # OUTSIDE the deploy timeout. A build FAILURE surfaces as Error — it is
    # a problem with the app, not the platform.
    def wokkud_build(app, deploy, server)
      DeployChannel.broadcast_to(deploy, { type: "log", data: "Building #{app.name} on the host via wokkud...\n" })

      unless wait_for_claim(deploy, server)
        raise BuilderUnavailable,
              "wokkud did not pick up the build (idle #{CLAIM_WAIT}s, queued past #{QUEUE_WAIT_MAX.inspect}, or agent heartbeat stale)"
      end

      with_deploy_timeout do
        sleep POLL until deploy.reload.build_finished_at.present?
        raise Error, "wokkud build failed: #{deploy.build_error}" if deploy.build_error.present?

        run_release!(app, deploy)
        ::Lifecycle::Ops.converge!(app, image_ref: deploy.wokkud_image_ref, deploy: deploy)
        deploy.reload.log.to_s
      end
    end

    # Procfile `release:` (Heroku release phase): a one-off container on the
    # NEW image, before switch-over. A failure fails the deploy and the old
    # version keeps serving. Skipped for previews — a preview may share the
    # parent's database, and a PR branch must not migrate production.
    def run_release!(app, deploy)
      cmd = deploy.formation_json&.dig("release").presence
      return if cmd.nil? || app.is_preview?

      append_log(deploy, "→ running release: #{cmd}\n")
      output = ::Lifecycle::Ops.run!(app, cmd, deploy: deploy)&.result&.dig("output").to_s
      append_log(deploy, output.end_with?("\n") ? output : "#{output}\n") if output.present?
    rescue ::Lifecycle::Ops::Failed => e
      raise Error, [ "release failed: #{e.message}", e.op&.result&.dig("output") ].compact.join("\n")
    end

    def append_log(deploy, text)
      Deploy.where(id: deploy.id).update_all([ "log = COALESCE(log, '') || ?", text ])
      DeployChannel.broadcast_to(deploy, { type: "log", data: text })
    end

    # Two clocks: the idle clock (CLAIM_WAIT seconds of builder-idle silence
    # = sick builder, today's semantics) resets while another claimed build
    # is provably in flight; the total clock caps queue time at
    # QUEUE_WAIT_MAX. A stale heartbeat bails immediately — the agent died
    # while we queued.
    def wait_for_claim(deploy, server)
      started = idle_since = Time.current
      announced_queue = false
      loop do
        return true if deploy.reload.build_picked_up_at.present?
        return false if server.reload.heartbeat_stale?
        return false if Time.current - started >= QUEUE_WAIT_MAX

        if builder_busy?(deploy, server)
          idle_since = Time.current
          unless announced_queue
            announced_queue = true
            msg = "wokkud builder busy — queued behind another build\n"
            deploy.update!(log: deploy.log.to_s + msg)
            DeployChannel.broadcast_to(deploy, { type: "log", data: msg })
          end
        elsif Time.current - idle_since >= CLAIM_WAIT
          return false
        end
        sleep POLL
      end
    end

    def builder_busy?(deploy, server)
      Deploy.joins(:app_record)
            .where(app_records: { server_id: server.id })
            .where(builder: "wokkud", build_finished_at: nil)
            .where.not(id: deploy.id)
            .where("build_picked_up_at > ?", BUSY_CLAIM_MAX_AGE.ago)
            .exists?
    end
  end
end
