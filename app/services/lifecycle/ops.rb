module Lifecycle
  # Assembles desired state for an app (image, formation, resources, env,
  # networking) and issues a stack.converge/stack.remove LifecycleOp for
  # wokkud to reconcile. Mirrors Services::Ops (issue + poll-to-terminal).
  class Ops
    class Failed < StandardError
      attr_reader :op
      def initialize(op) = (@op = op; super("#{op.kind} failed: #{op.error} (#{op.error_code})"))
    end
    class Timeout < StandardError; end
    class EmptyFormation < StandardError; end
    # Raised by issue! when LifecycleOp.create! collides with the one-live-op
    # partial unique index (index_lifecycle_ops_one_live_per_app) — a
    # restart/scale/wake/rollback/deploy already has a pending/claimed op in
    # flight for this app. Typed so callers can distinguish "try again" from
    # Failed/Timeout instead of an unmapped ActiveRecord::RecordNotUnique
    # crashing the job (the rollback-wedges-deploy bug this fixes).
    class Busy < StandardError
      attr_reader :app
      def initialize(app) = (@app = app; super("another operation is in flight for #{app.name} — retry shortly"))
    end
    PORT_RANGE = 20_000..29_999
    POLL_INTERVAL = 2
    # Adopt's on-host curl gate (lib/tasks/lifecycle.rake): a fresh Swarm task
    # needs a few seconds to start and bind before it answers.
    ADOPT_CURL_ATTEMPTS = 10
    ADOPT_CURL_INTERVAL = 3

    # Historical lifecycle_ops rows predate B5b and carry the legacy shape.
    # converge! falls back to the last succeeded op for an adopted app's
    # image and commands, so both shapes must read. Getting this wrong
    # silently reverts a restarted app to its image CMD — the B5a bug that
    # took voucher-bot down for ~2 minutes.
    def self.image_ref_from(params)
      return nil if params.blank?
      params["image_ref"].presence ||
        params.dig("services")&.values&.filter_map { |s| s["image"].presence }&.first
    end

    def self.formation_commands_from(params)
      return {} if params.blank?
      return params["formation_commands"] if params["formation_commands"].present?
      (params["services"] || {}).each_with_object({}) do |(name, svc), h|
        h[name] = svc["command"] if svc["command"].present?
      end
    end

    def self.converge!(app, image_ref: nil, formation: nil, restart: false, tag_from_local: false, wait: true,
                        timeout: 630, allow_empty: false, deploy: nil, formation_commands: nil)
      # A caller mid-deploy passes the in-flight deploy explicitly (it's still
      # :building, so the latest-succeeded fallback would run the PREVIOUS
      # deploy's Procfile commands — the exact word-split bug B5a fixes).
      # Everyone else (restart/scale/sleep/wake/adopt) falls back to the last
      # succeeded deploy for image_ref/formation_commands/deploy_id.
      deploy ||= app.deploys.where(status: :succeeded).order(created_at: :desc).first
      # Only a wokkud-built deploy has an image in the registry — a dokku-built
      # deploy's wokkud_image_ref points at a tag that was never pushed, so
      # defaulting to it makes converge fail image_pull_failed (adopt of a
      # pre-Track-A app). Registry-back the ref only when it's really there.
      image_ref ||= deploy&.wokkud_image_ref if deploy&.builder == "wokkud"
      # Apps adopted via tag_from_local never get a wokkud-built Deploy row —
      # the adopt-minted ref (pushed to the registry by that converge) is the
      # only image source until the app's first wokkud build. Fall back to
      # the last succeeded stack.converge op's own params before giving up —
      # for the image_ref AND the formation_commands snapshot (a dokku-built
      # deploy has no formation_json, so without this every post-adopt
      # restart/scale would silently revert the task to the image's CMD).
      prev_converge = app.lifecycle_ops.succeeded.where(kind: "stack.converge").order(:created_at).last
      image_ref ||= image_ref_from(prev_converge&.params)
      raise ArgumentError, "no image for #{app.name} — deploy first or pass tag_from_local" if image_ref.blank? && !tag_from_local
      # Adopt push target for the dokku-built local image (spec §3.6): same
      # registry/repo convention as Deploy#wokkud_image_ref, tagged with an
      # adopt timestamp instead of a deploy id since there's no Deploy row yet.
      image_ref ||= "#{Hosts::Registry::HOST}/wokku/#{app.name}:adopt-#{Time.current.to_i}" if tag_from_local

      # Symbol-keyed formations (runbook smoke commands, callers passing
      # { web: 2 }) must survive the guard and match the string-keyed
      # process_scales the agent reconciles against.
      desired = (formation || current_formation(app)).transform_keys(&:to_s)
      guard_formation!(app, desired) unless allow_empty
      # dokku injects PORT at container create; Swarm tasks only get env from
      # these params, and ingress TargetPort routes to container_port — the
      # process must bind exactly that, so PORT is forced to match (first-rung
      # smoke: node app bound 3000, TargetPort 5000, ingress unreachable).
      env = app.runtime_env.merge("PORT" => app.container_port.to_s)
      # Precedence: explicit override (adopt's dokku-argv snapshot — dokku
      # bakes the Procfile command into the container, not the image) >
      # a wokkud-built deploy's formation_json (even empty: the new image's
      # own CMD is the truth after a real build) > the previous converge
      # op's persisted commands (keeps tag_from_local apps on dokku's argv
      # across restarts/scales) > image CMD.
      commands = formation_commands
      if commands.nil? && deploy&.builder == "wokkud"
        # Wokkud execs these arrays directly as the container command,
        # bypassing the image entrypoint — nixpacks images only put venv
        # binaries on PATH via their bash -l entrypoint (kb-bot: bare
        # `uvicorn` not found in $PATH). Wrap through a login shell, exec'ing
        # so the app still ends up PID 1. Adopt argv snapshots and previously
        # persisted commands already carry their entrypoint semantics — never
        # re-wrap those paths.
        # ponytail: commands containing single quotes or control operators
        # keep the raw exec-array form (splitCommand has no escapes; exec
        # doesn't compose with &&) — none exist in prod Procfiles today.
        commands = (deploy.formation_json || {}).transform_values do |c|
          c.to_s.match?(/['|;&]/) ? c : "/bin/bash -l -c 'exec #{c}'"
        end
      end
      commands ||= formation_commands_from(prev_converge&.params)
      # Swarm ContainerSpec commands exec directly — no shell, so no $VAR
      # expansion (wicara-rails' Procfile `-p $PORT` crash-looped with a
      # literal "$PORT"). The env is fully assembled above; bake the values
      # in. Unknown vars stay untouched — visible beats silently vanishing.
      commands = commands.transform_values { |c|
        c.to_s.gsub(/\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/) { env.key?($1) ? env[$1] : $~[0] }
      }
      res = resources_for(app, desired.keys)
      services = desired.each_with_object({}) do |(proc, count), h|
        svc = {
          "image" => image_ref,
          "command" => commands[proc],
          "replicas" => count,
          "env" => env,
          "memory_mb" => res.dig(proc, :memory_mb),
          "cpu" => res.dig(proc, :cpu),
          "public" => (proc == "web")
        }
        if proc == "web"
          svc["target_port"] = app.container_port
          svc["mounts"] = app.mounts_for_converge if app.mounts_for_converge.any?
          svc["healthcheck"] = app.healthcheck_json if app.healthcheck_json.present?
        end
        h[proc] = svc.compact
      end

      params = {
        deploy_id: deploy&.id, image_ref: image_ref,
        # Legacy trio stays alongside `services` until the agent floor is
        # raised: an agent rollback must not strand a Rails that only speaks
        # the new shape. Agent prefers `services` when present.
        formation: desired,
        formation_commands: commands,
        env: env,
        resources: res,
        services: services,
        published_port: allocate_swarm_port!(app),
        container_port: app.container_port,
        networks: [ DatabaseProvisioner::DEDICATED_NETWORK ],
        restart: restart, tag_from_local: tag_from_local,
        local_ref: (tag_from_local ? "dokku/#{app.name}:latest" : nil)
      }.compact
      issue!(app, "stack.converge", params, wait: wait, timeout: timeout)
    end

    def self.remove!(app, wait: true) = issue!(app, "stack.remove", {}, wait: wait, timeout: 330)

    # One-off command in a fresh container from the app's image (stack.run):
    # dokku-`run` semantics on Swarm — post_deploy migrations + the future
    # `wokku run`. Assembly mirrors converge!: same image fallback chain, same
    # env, same bash -l wrap rule for wokkud-built (nixpacks) images, same
    # $VAR baking (job commands exec without a shell). Not interactive —
    # that's container.exec, a different op.
    def self.run!(app, command, timeout: 630, wait: true, deploy: nil)
      raise ArgumentError, "run! needs a command" if command.blank?

      # A caller mid-deploy passes the in-flight deploy explicitly (it's still
      # :building, so the latest-succeeded lookup would miss it — on a FIRST
      # deploy that meant no deploy at all, so the wokkud bash -l wrap never
      # applied and post_deploy died with `env: ruby not found`). Same rule
      # as converge!.
      deploy ||= app.deploys.where(status: :succeeded).order(created_at: :desc).first
      image_ref = deploy&.wokkud_image_ref if deploy&.builder == "wokkud"
      prev_converge = app.lifecycle_ops.succeeded.where(kind: "stack.converge").order(:created_at).last
      image_ref ||= image_ref_from(prev_converge&.params)
      raise ArgumentError, "no image for #{app.name} — deploy first" if image_ref.blank?

      env = app.runtime_env.merge("PORT" => app.container_port.to_s)
      cmd = command.to_s
      if deploy&.builder == "wokkud" && !cmd.match?(/['|;&]/)
        cmd = "/bin/bash -l -c 'exec #{cmd}'"
      end
      cmd = cmd.gsub(/\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/) { env.key?($1) ? env[$1] : $~[0] }

      res = resources_for(app, [ "run" ])["run"] || {}
      params = {
        image_ref: image_ref, command: cmd, env: env,
        memory_mb: res[:memory_mb], cpu: res[:cpu],
        networks: [ DatabaseProvisioner::DEDICATED_NETWORK ]
      }.compact
      issue!(app, "stack.run", params, wait: wait, timeout: timeout)
    end

    # Destroy-path convenience: tear down a flagged app's Swarm stack before
    # the record cascade (lifecycle_ops is dependent: :destroy). Op failures
    # are logged and swallowed — the record still goes, an operator prunes any
    # orphaned services. No-op for unflagged apps.
    def self.remove_if_flagged!(app)
      return unless app.wokkud_lifecycle?
      remove!(app, wait: true)
    rescue Failed, Timeout, Busy, ActiveRecord::RecordNotUnique => e
      # Busy: issue! now converts a live-op collision (e.g. destroy-during-
      # deploy) into this typed error itself. RecordNotUnique stays in the
      # list as belt-and-suspenders in case anything ever inserts a
      # LifecycleOp outside issue!. Log and let the destroy proceed; the
      # janitor/next converge unwedges the lane.
      Rails.logger.warn("Lifecycle::Ops.remove_if_flagged!(#{app.name}): #{e.class}: #{e.message}")
    end

    SWARM_PORT_ALLOCATION_ATTEMPTS = 5

    def self.allocate_swarm_port!(app)
      return app.swarm_port if app.swarm_port.present?
      attempts = 0
      begin
        app.with_lock do
          next app.swarm_port if app.reload.swarm_port.present?
          taken = AppRecord.where.not(swarm_port: nil).maximum(:swarm_port) || (PORT_RANGE.first - 1)
          raise "swarm_port range exhausted" if taken >= PORT_RANGE.last
          app.update!(swarm_port: taken + 1)
          app.swarm_port
        end
      rescue ActiveRecord::RecordNotUnique
        # ponytail: the maximum(:swarm_port) read isn't locked across apps, so two
        # concurrent first-time allocations can race onto the same port; the unique
        # index catches it and we just retry the read+write a few times.
        attempts += 1
        raise if attempts >= SWARM_PORT_ALLOCATION_ATTEMPTS
        retry
      end
    end

    # process_scales' quantity column is named `count` in the schema
    # (db/migrate/20260313060636_create_process_scales.rb) — the brief's
    # skeleton said "quantity"; using the real column name.
    def self.current_formation(app)
      scales = app.process_scales.where("count > 0").pluck(:process_type, :count).to_h
      scales.presence || { "web" => 1 }
    end

    # Legacy `dokku ps:stop` stops EVERY process type; the flagged equivalent
    # zeroes every process in the current formation (converge with allow_empty).
    def self.stop_formation(app) = current_formation(app).transform_values { 0 }

    def self.guard_formation!(app, desired)
      had_web = current_formation(app)["web"].to_i.positive?
      return unless had_web && (!desired.key?("web") || desired["web"].to_i.zero?)
      raise EmptyFormation, "formation omits web while app runs web — pass web: N explicitly (formation_would_empty)"
    end

    # Per-process resources (spec 2026-09-24): each process type uses its own
    # DynoAllocation shape; a type with no row (a new Procfile entry, the
    # one-off `run`) inherits web's. Tier-only rows (legacy + sleeping)
    # resolve through the tier, so pre-shape apps converge exactly as before.
    def self.resources_for(app, process_types)
      allocs = app.dyno_allocations.includes(:dyno_tier).index_by(&:process_type)
      process_types.index_with do |proc|
        a = allocs[proc] || allocs["web"]
        a ? { memory_mb: a.effective_memory_mb, cpu: a.effective_cpu } : {}
      end
    end

    def self.issue!(app, kind, params, wait:, timeout:)
      op = begin
        LifecycleOp.create!(app_record: app, server: app.server, kind: kind, params: params)
      rescue ActiveRecord::RecordNotUnique
        # index_lifecycle_ops_one_live_per_app: another pending/claimed op
        # already exists for this app. Convert to a typed error every caller
        # can rescue by name instead of leaving raw RecordNotUnique unmapped
        # in job rescue chains (the rollback/deploy-wedge bug this fixes).
        raise Busy, app
      end
      return op unless wait
      deadline = Time.current + timeout
      loop do
        op.reload
        return op if op.succeeded?
        raise Failed, op if op.failed?
        raise Timeout, "#{kind} on #{app.name} not finished after #{timeout}s" if Time.current > deadline
        sleep POLL_INTERVAL
      end
    end
  end
end
