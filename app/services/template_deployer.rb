require "shellwords"

class TemplateDeployer
  # A native app reads env ONLY from EnvVar rows (W3). On a server that isn't
  # wokkud-services-flagged, DatabaseProvisioner falls back to the legacy
  # dokku-plugin branch, which writes NO EnvVar row — the app would boot with
  # no DATABASE_URL at all, with no error anywhere. Refuse native creation on
  # such a server instead.
  class ServerNotServiceFlagged < StandardError; end

  attr_reader :template, :app_name, :server, :user, :deploy, :log

  def initialize(template:, app_name:, server:, user:, deploy: nil, on_progress: nil)
    @template = template
    @app_name = app_name
    @server = server
    @user = user
    @deploy = deploy
    @on_progress = on_progress
    @log = []
  end

  def deploy!
    # B5b Task 7: every template deploys natively now. Image templates
    # converge an image; repo templates build through the wokkud git path.
    # The only surviving branch is the deploy STEP below (converge vs build)
    # — creation, resources, provisioning and the guards are unconditional.
    image_template = template[:deploy_method] == "docker_image" && template[:docker_image].present?

    # A native app requires wokkud-managed services to have a reachable
    # database (dedicated_db_engine/shared_engines and alias_database_url!/
    # expand_url_components! all depend on the EnvVar row DatabaseProvisioner
    # only writes on the wokkud-ops path). Refuse before provisioning
    # anything rather than silently booting a half-configured app.
    unless server.wokkud_services_enabled?
      raise ServerNotServiceFlagged,
            "template #{template[:slug] || app_name} deploys natively but server " \
            "#{server.name} is not wokkud-services-flagged — a native app requires wokkud-managed " \
            "services to have a reachable database"
    end

    step("Creating app #{app_name}...") do
      AppRecord.find_or_initialize_by(name: app_name, server: server).tap do |a|
        a.assign_attributes(
          # Use the deploying user's own team. server.team is the
          # platform admin team on wokku.cloud (servers are shared
          # infra) — assigning the app there would hide it from the
          # customer's dashboard.
          team: user.teams.first,
          creator: user,
          deploy_branch: template[:branch] || "main",
          git_repository_url: template[:repo],
          status: :deploying,
          # converge (image) / the build (repo) both read the port and the
          # volume list off the record, so they're set once here rather than
          # recomputed from the template on every later restart/scale/wake.
          container_port: template[:container_port] || 3000,
          storage_mounts: Array(template[:storage_mounts]),
          healthcheck_json: template[:healthcheck],
          wokkud_native: true, wokkud_routed: true,
          wokkud_git: true, wokkud_lifecycle: true
        )
        a.save!
      end
    end

    app = AppRecord.find_by!(name: app_name, server: server)

    # Container tier: templates that ship with addons (n8n + postgres,
    # ghost + mysql, etc.) need real RAM. Match the UI/pricing helper's
    # assumption (basic) instead of dropping every customer onto free
    # — the cost card on the template page already advertises basic.
    step("Setting resource limits...") do
      tier = container_tier(app)
      shape = builder_shape_for(tier) if tier
      if shape && !app.dyno_allocations.exists?(process_type: "web")
        check_builder_shape!(app, shape)
        app.dyno_allocations.create!(process_type: "web", cpu: shape.cpu, memory_mb: shape.memory_mb, count: 1)
      elsif tier
        app.dyno_allocations.find_or_create_by!(process_type: "web") do |a|
          a.dyno_tier = tier
          a.count = 1
        end
        # Native apps get their limits from the converge params —
        # Lifecycle::Ops.resources_for reads the tier off the allocation above.
      end
    end

    # Bundle v2 (backlog 4.7): if the template declares `shared_engines:`
    # or `dedicated_db_engine:`, those are the source of truth and we route
    # through the matching provisioners. Templates that haven't migrated
    # still use the legacy `addons:` array below.
    shared_engines      = template[:shared_engines] || []
    dedicated_db_engine = template[:dedicated_db_engine]
    bundle_v2_path      = shared_engines.any? || dedicated_db_engine.present?

    if bundle_v2_path
      shared_engines.each do |engine|
        step("Attaching shared #{engine}...") do
          Addons::SharedProvisioner.new(app: app, engine: engine).call
        end
      end

      if dedicated_db_engine
        step("Provisioning dedicated #{dedicated_db_engine}...") do
          provision_dedicated_db!(app, dedicated_db_engine)
        end
      end
    else
      (template[:addons] || []).each do |addon|
        step("Provisioning #{addon['type']}...") do
          provision_dedicated_db!(app, addon["type"],
                                  tier_name: addon["tier"] || addon[:tier] || "basic")
        end
      end
    end

    if template[:env].present?
      step("Setting environment variables...") do
        Apps::EnvWriter.set(app, template[:env])
      end
    end

    if template[:postgres_components]
      step("Expanding DATABASE_URL into #{template[:postgres_components]}* components...") do
        expand_url_components!(app, url_key: "DATABASE_URL", prefix: template[:postgres_components], default_port: 5432)
      end
    end

    if template[:mysql_components]
      step("Expanding DATABASE_URL into #{template[:mysql_components]}* components...") do
        expand_url_components!(app, url_key: "DATABASE_URL", prefix: template[:mysql_components], default_port: 3306)
      end
    end

    if template[:mongo_components]
      step("Expanding DATABASE_URL into #{template[:mongo_components]}* components...") do
        expand_url_components!(app, url_key: "DATABASE_URL", prefix: template[:mongo_components], default_port: 27017)
      end
    end

    if template[:set_url].present?
      step("Setting public URL env vars: #{template[:set_url].join(', ')}...") do
        apply_set_url!(app, app_name, keys: template[:set_url])
      end
    end

    if template[:generate_secrets].present?
      step("Generating random secrets: #{template[:generate_secrets].join(', ')}...") do
        apply_generate_secrets!(app, keys: template[:generate_secrets])
      end
      @log << {
        step: "Hint: open the app's Environment Variables to copy the generated values for #{template[:generate_secrets].join(', ')}.",
        at: Time.current
      }
    end

    if template[:alias_env].present?
      step("Aliasing env vars: #{template[:alias_env].map { |t, s| "#{s}→#{t}" }.join(', ')}...") do
        apply_alias_env!(app, aliases: template[:alias_env])
      end
    end

    if image_template
      # `::` is load-bearing: TemplateDeployer resolves bare `Lifecycle` to
      # Apps::Lifecycle on some call paths — the namespace trap that has now
      # bitten this codebase three times.
      step("Deploying image #{template[:docker_image]}...") do
        ::Lifecycle::Ops.converge!(
          app,
          image_ref: template[:docker_image],
          formation: { "web" => 1 },
          # Some images' CMD isn't the server (chatwoot ships `irb`) — the
          # compose main service's command: overrides it when present.
          formation_commands: (template[:command].present? ? { "web" => template[:command] } : nil)
        )
      end

      if template[:post_deploy].present?
        step("Running post-deploy: #{template[:post_deploy]}...") do
          ::Lifecycle::Ops.run!(app, template[:post_deploy])
        rescue ::Lifecycle::Ops::Failed => e
          # Failed#initialize composes its own message from the op — inject
          # the failed command's own output (TarballDeployJob's idiom) so the
          # generic rescue below doesn't surface a bare "stack.run failed:
          # ... (command_failed)" with no clue what the command printed.
          out = e.op&.result&.dig("output")
          raise e, [ e.message, out ].compact.join("\n") if out.present?
          raise
        end
      end

      # converge! is synchronous, so the image path owns its own tail: DNS
      # first (LE verifies via DNS lookup), then status. Caddy owns TLS for
      # native apps and issues on demand — no cert push.
      step("Configuring DNS...") do
        Wokku.config.dns_provider.create_app_record(app_name, server.host)
      rescue => e
        @log << { step: "DNS setup skipped: #{e.message}", at: Time.current }
      end
      @log << { step: "SSL handled by the router — no certificate push needed.", at: Time.current }

      app.update!(status: :running)
      @log << { step: "Deploy complete!", at: Time.current }
      @on_progress&.call("Deploy complete!")

      { success: true, app: app, log: @log }
    else
      # Repo templates build through the exact path GithubDeployJob takes for
      # a wokkud_git app: fetch into the app's own bare repo, then hand off to
      # PushDeployer. A Dockerfile in the build context is honoured by the
      # wokkud builder automatically — no builder:set equivalent needed.
      step("Fetching #{template[:repo]} and building...") do
        branch = template[:branch] || "main"
        repo = Git::BareRepo.new(app_name)
        repo.ensure!
        GithubDeployJob.system_fetch(repo, template[:repo], branch)
        # PushDeployer hex-validates the sha, so resolve the ref we just
        # fetched rather than passing the branch name.
        sha = resolve_sha(repo, branch)
        Git::PushDeployer.new(app, sha: sha, ref: "refs/heads/#{branch}", deploy: deploy).call
      end

      # ASYNC HANDOFF. PushDeployer#call only ENQUEUES TarballDeployJob and
      # returns — the build hasn't happened yet. That job chain is the sole
      # owner of the Deploy's terminal status, app status:running, and DNS/SSL
      # (via PostDeploySetupJob). deploy! must NOT run the inline tail here or
      # it double-registers DNS and races the job. Link the Deploy to the app
      # for the UI and stop; `success: true` here means "build enqueued".
      #
      # post_deploy can't run inline here — the build is async (TarballDeployJob
      # owns the tail). Ride the Deploy row; the job runs it after converge.
      deploy&.update!(app_record: app, run_after_deploy: template[:post_deploy].presence)
      @log << { step: "Build enqueued — deploy continues in the background.", at: Time.current }
      @on_progress&.call("Build enqueued — deploy continues in the background.")

      { success: true, async: true, app: app, log: @log }
    end
  rescue => e
    @log << { step: "Error", message: e.message, at: Time.current }
    @on_progress&.call("Deploy failed: #{e.message}. Rolling back...")
    rollback_partial_deploy!(e)
    { success: false, error: e.message, log: @log }
  end

  # Clean up any partially-created resources when a deploy step fails,
  # but PRESERVE the Rails AppRecord + Deploy row so the user can read
  # what went wrong. Previous behaviour hard-deleted everything, which
  # left users at a 404 with zero explanation.
  #
  # Host-side (app, DBs, DNS) is still cleaned so the host doesn't accumulate
  # half-provisioned junk — every template app is native now, so removal is
  # always a stack.remove op.
  def rollback_partial_deploy!(original_error)
    app = AppRecord.find_by(name: app_name, server: server)
    return unless app

    begin
      app.app_databases.includes(:database_service).each do |ad|
        db = ad.database_service
        next unless db
        # DatabaseProvisioner.destroy! branches wokkud-managed →
        # service.destroy op vs dokku plugin, and destroys the row either way.
        DatabaseProvisioner.destroy!(database_service: db)
      rescue StandardError => e
        @log << { step: "Rollback warning: could not clean up database #{db.name}", error: e.message, at: Time.current }
      end

      Wokku.config.dns_provider.delete_app_record(app_name) rescue nil
      ::Lifecycle::Ops.remove!(app) rescue nil
    rescue StandardError => cleanup_error
      @log << { step: "Cleanup warning", error: cleanup_error.message, at: Time.current }
      Rails.logger.warn("TemplateDeployer cleanup warning: #{cleanup_error.message} (original: #{original_error.message})")
    end

    # Write a failed Deploy record (or update the existing one) so the
    # user's deploy URL stays valid and shows the log + error.
    app.update!(status: :crashed)
    deploy = app.deploys.order(created_at: :desc).first
    log_payload = { error: original_error.message, steps: @log }.to_json
    if deploy
      deploy.update!(status: :failed, log: log_payload, finished_at: Time.current)
    else
      app.deploys.create!(
        status: :failed,
        log: log_payload,
        started_at: @log.first&.dig(:at) || Time.current,
        finished_at: Time.current
      )
    end
  end

  # Container tier follows the app's resolved box_size (set by the quota
  # resolver at create time) so an auto-upgraded box — e.g. a Team user
  # deploying a small-min template onto a large box — actually runs on,
  # and counts against quota as, that size. Falls back to the template's
  # min_tier, then basic/free, for apps created without a box_size.
  def container_tier(app)
    tier_name = DynoTier::BOX_SIZE_TO_DYNO_TIER[app.box_size.to_s].presence ||
                template[:min_tier].presence ||
                ((template[:addons] || []).any? ? "basic" : "free")
    DynoTier.find_by(name: tier_name) || DynoTier.order(:monthly_price_cents).first
  end

  def build_steps
    steps = [ { action: :create_app, detail: app_name } ]

    shared_engines      = template[:shared_engines] || []
    dedicated_db_engine = template[:dedicated_db_engine]

    if shared_engines.any? || dedicated_db_engine.present?
      shared_engines.each do |engine|
        steps << { action: :attach_shared, detail: engine }
      end
      steps << { action: :provision_dedicated, detail: dedicated_db_engine } if dedicated_db_engine
    else
      (template[:addons] || []).each do |addon|
        steps << { action: :provision_addon, detail: addon }
      end
    end

    steps << { action: :set_env, detail: template[:env] } if template[:env].present?

    if template[:disable_init_process] || template[:disable_zero_downtime_checks]
      flags = []
      flags << "init-process=false" if template[:disable_init_process]
      flags << "checks-disabled"    if template[:disable_zero_downtime_checks]
      steps << { action: :deploy_compat, detail: flags.join(", ") }
    end

    steps << { action: :deploy, detail: template[:repo] }
    steps << { action: :post_deploy, detail: template[:post_deploy] } if template[:post_deploy].present?

    steps
  end

  private

  # B5b Task 6: this used to be a private copy of DatabaseProvisioner that
  # called `dokku <engine>:create` + `:link` directly. The link wired
  # DATABASE_URL into dokku's config only — invisible to a converged app,
  # whose env comes from EnvVar rows alone (W3). Routing through the real
  # provisioner picks up the wokkud service.create path, the shared/dedicated
  # branch, EnvWriter, and the network attach, and drops two Dokku call sites.
  # It also raises on an engine wokkud has no image for, rather than silently
  # provisioning something the app can never reach.
  def provision_dedicated_db!(app, engine, tier_name: "basic")
    shape = builder_service_shape_for(engine, tier_name)
    check_builder_shape!(app, shape) if shape
    db = DatabaseProvisioner.new(
      app: app, service_type: engine, tier: tier_name, creator: user, shape: shape
    ).call
    alias_database_url!(app, engine)
    # 1.8: addon cost is bundled into the user's plan invoice. No
    # per-addon billing segment.

    # Cap the container to the plan's tier (memory / max_connections) —
    # without this every template-provisioned dedicated db ships uncapped.
    ApplyDatabaseTierJob.perform_later(db.id)
    db
  end

  # Per-resource billing (spec 2026-09-24): with the builder on, a tier-only
  # row bills Rp0, so templates are born shaped — the tier's size rounded up
  # onto the grid exactly as the cloud's Billing::ShapeBackfill does. Free
  # sleeping stays a tier (sleeping is tier-driven). nil = legacy tier row.
  def builder_shape_for(tier)
    return unless Wokku.config.resource_builder? && !tier.sleeps
    Resources::Shape.round_up(cpu: tier.cpu_shares, memory_mb: tier.memory_mb)
  end

  def builder_service_shape_for(engine, tier_name)
    return unless Wokku.config.resource_builder?
    spec = ServiceTier.find_by(service_type: engine.to_s, name: tier_name)&.spec || {}
    mem = spec["memory_mb"].to_i
    if mem.zero?
      preset = Resources::Shape::SERVICE_PRESETS.dig(engine.to_s, "small")
      return preset && Resources::Shape.new(**preset)
    end
    Resources::Shape.round_up(cpu: mem / 2048.0, memory_mb: mem, disk_gb: [ spec["storage_gb"].to_i, 1 ].max)
  end

  # Same enforcer + capacity gate the builder runs for a new shape. Not
  # Resources::ApplyChange.call: that enqueues a resize converge on a
  # non-`created` app, which would race this deploy.
  def check_builder_shape!(app, shape)
    check = Resources::ApplyChange.check_new_shape(team: app.team, server: app.server, shape: shape)
    raise check.error unless check.ok
  end

  # DatabaseProvisioner names the connection var after the engine
  # ("#{service_type.upcase}_URL" → POSTGRES_URL, MARIADB_URL, …), but every
  # piece of template metadata keys off DATABASE_URL: `env:` interpolation,
  # `postgres_components:`/`mysql_components:`/`mongo_components:` (whose
  # expansion hardcodes that key), `alias_env:` sources, and `set_url:`.
  # Without this bridge those templates silently no-op and the app boots with
  # no database — the failure mode is a running container, not an error.
  # Only fills a gap: a template declaring its own DATABASE_URL keeps it.
  def alias_database_url!(app, engine)
    env = app.runtime_env
    return if env["DATABASE_URL"].present?
    url = env["#{engine.to_s.upcase}_URL"]
    return if url.blank?
    Apps::EnvWriter.set(app, { "DATABASE_URL" => url })
  end

  def step(message)
    @log << { step: message, at: Time.current }
    @on_progress&.call(message)
    yield
  rescue => e
    @log << { step: "Failed: #{message}", error: e.message, at: Time.current }
    @on_progress&.call("FAILED: #{message} — #{e.message}")
    raise
  end

  # Resolve the sha the fetch just landed on the bare repo. PushDeployer
  # hex-validates the sha before it reaches `git archive`, so we resolve the
  # branch to a concrete commit rather than passing the branch name through.
  def resolve_sha(repo, branch)
    sha = `git -C #{Shellwords.escape(repo.path)} rev-parse refs/heads/#{Shellwords.escape(branch)}`.strip
    raise "could not resolve #{branch} after fetch" unless sha.match?(/\A[0-9a-f]{40}\z/)
    sha
  end

  # Some apps (n8n, strapi, keycloak) don't accept DATABASE_URL — they
  # want DB_POSTGRESDB_HOST, DB_POSTGRESDB_PORT, etc. as separate vars.
  # Dokku's postgres plugin only exposes DATABASE_URL, so after linking
  # we parse it and set the component vars explicitly.
  # Parse a DB connection URL (DATABASE_URL from Dokku's postgres/mysql/mongo
  # addon) into 5 per-component env vars, using the provided prefix. The
  # key suffixes follow n8n's convention (HOST/PORT/DATABASE/USER/PASSWORD)
  # which most apps either match directly or accept with a different prefix.
  # Ghost's "database__connection__host" is one example; DB_POSTGRESDB_* is
  # another.
  def expand_url_components!(app, url_key:, prefix:, default_port:)
    url = app.runtime_env[url_key]
    return if url.blank?

    # Suffix case follows the prefix. DB_POSTGRESDB_ → uppercase suffixes
    # (HOST/PORT/…). database__connection__ → lowercase (host/port/…).
    # Ghost explicitly demands lowercase; n8n demands uppercase; the prefix
    # is the unambiguous signal for which convention the target app uses.
    suffixes = prefix.match?(/[a-z]/) ?
      %w[host port database user password] :
      %w[HOST PORT DATABASE USER PASSWORD]

    uri = URI.parse(url)
    components = {
      "#{prefix}#{suffixes[0]}" => uri.host,
      "#{prefix}#{suffixes[1]}" => (uri.port || default_port).to_s,
      "#{prefix}#{suffixes[2]}" => uri.path.to_s.sub(%r{\A/}, ""),
      "#{prefix}#{suffixes[3]}" => uri.user.to_s,
      "#{prefix}#{suffixes[4]}" => URI.decode_www_form_component(uri.password.to_s)
    }
    Apps::EnvWriter.set(app, components)
  end

  # Read SOURCE env var and set TARGET to the same value. Used when an app
  # expects a differently-named var than what provisioning wrote (e.g. Hasura
  # wants HASURA_GRAPHQL_DATABASE_URL, provisioning sets DATABASE_URL).
  # Source is the control plane (EnvVar rows), which W3 made the truth for
  # every app — reading dokku's config here returned a value the runtime
  # already ignores.
  def apply_alias_env!(app, aliases:)
    env = app.runtime_env
    vars = aliases.each_with_object({}) do |(target, source), h|
      val = env[source].to_s.strip
      h[target] = val if val.present?
    end
    return if vars.empty?
    Apps::EnvWriter.set(app, vars)
  end

  # Generate a cryptographically strong random value for each requested env key
  # and persist to the EnvVar mirror. Skip any key that already exists so
  # redeploys don't rotate live credentials.
  def apply_generate_secrets!(app, keys:)
    vars = keys.each_with_object({}) do |key, h|
      next if app.env_vars.exists?(key: key)
      h[key] = SecureRandom.urlsafe_base64(32)
    end
    return if vars.empty?
    Apps::EnvWriter.set(app, vars)
  end

  # Some apps (Ghost's `url=`, Plausible's `BASE_URL=`, etc.) refuse to boot
  # unless told their own public URL. Dokku sets this up via domains but
  # the app reads it from an env var.
  def apply_set_url!(app, app_name, keys:)
    url = "https://#{app_name}.#{Wokku.config.canonical_domain}"
    vars = keys.each_with_object({}) { |k, h| h[k] = url }
    Apps::EnvWriter.set(app, vars)
  end
end
