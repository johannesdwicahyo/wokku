class TemplateParser
  ADDON_IMAGES = {
    "postgres" => "postgres", "postgresql" => "postgres",
    "mysql" => "mysql", "mariadb" => "mariadb",
    "redis" => "redis", "mongo" => "mongodb", "mongodb" => "mongodb",
    "memcached" => "memcached", "rabbitmq" => "rabbitmq",
    "elasticsearch" => "elasticsearch", "minio" => "minio",
    "pgvector" => "postgres"
  }.freeze

  def self.parse(yaml_content, slug:)
    metadata = extract_metadata(yaml_content)
    compose = YAML.safe_load(yaml_content, permitted_classes: [ Symbol ]) || {}
    services = compose["services"] || {}

    main_service_name, main_service = find_main_service(services)
    addons = extract_addons(services, main_service_name)

    image = main_service&.dig("image")
    port = metadata["port"]&.to_i || extract_port(main_service)

    env = {}
    (main_service&.dig("environment") || []).each do |e|
      if e.is_a?(String) && e.include?("=")
        key, value = e.split("=", 2)
        env[key] = value unless value&.start_with?("${")
      end
    end

    {
      name: metadata["name"] || slug.tr("-", " ").titleize,
      slug: slug,
      description: metadata["slogan"] || metadata["description"] || "",
      category: metadata["category"] || "uncategorized",
      icon: metadata["icon"] || "docker",
      # Simple Icons brand slug (e.g. "nextdotjs", "rubyonrails"). When
      # present, the gallery renders the real brand SVG via
      # cdn.simpleicons.org instead of the generic emoji.
      icon_slug: metadata["icon_slug"].to_s.strip.presence,
      # Brand color for the simpleicons CDN — six hex chars, no leading
      # `#`. simpleicons defaults to black on a light background; we
      # pass a brand color so the icon stays recognizable on the dark
      # surface. Fall back to neutral white when unset.
      icon_color: metadata["icon_color"].to_s.strip.presence || "FFFFFF",
      # Framework/app version surfaced as a small badge on cards. Keep
      # short ("8.1", "11", "1.23"). The starter scaffold's actual
      # framework version is the source of truth — this field exists
      # so the gallery can advertise it.
      version: metadata["version"].to_s.strip.presence,
      repo: metadata["documentation"] || "",
      branch: "main",
      tags: (metadata["tags"] || "").split(",").map(&:strip),
      # `# hidden: true` keeps a template out of the gallery and API until it can deploy.
      hidden: metadata["hidden"].to_s.strip == "true",
      deploy_method: image ? "docker_image" : "git",
      docker_image: image,
      container_port: port,
      addons: addons,
      env: env,
      post_deploy: metadata["post_deploy"] || "",
      # Container healthcheck (agent wire shape, defaults filled here — the
      # single source of defaults). Swarm start-first counts a task healthy
      # the instant it Runs; slow-boot images (ghost/umami ~60s) need this
      # or they blip on every rollout. Absent key => nil => image's own
      # HEALTHCHECK is preserved and spec hashes don't change.
      healthcheck: healthcheck_from(metadata),
      # Compose `command:` on the main service — required when the image's
      # own CMD isn't the server (chatwoot's is `irb`). String or exec-array
      # form both normalize to one string; converge splits it wokkud-side.
      command: Array(main_service&.dig("command")).join(" ").presence,
      # Minimum dyno tier name. Templates that need more than 256 MB at boot
      # (WAHA's headless Chromium, anything heavy) should set
      # `# min_tier: basic` so users don't land on the 256 MB free tier and
      # immediately OOM.
      min_tier: metadata["min_tier"].to_s.strip.presence,
      # Apps that want DATABASE_URL broken into individual host/port/user/
      # password/database env vars. Each flag declares the per-var name prefix;
      # the deployer writes <PREFIX>HOST, <PREFIX>PORT, etc. after linking.
      #
      #   postgres_components: true                  # n8n default → DB_POSTGRESDB_*
      #   mysql_components: database__connection__   # Ghost → database__connection__host etc.
      #   mongo_components: MONGODB_                 # MongoDB-backed apps
      #
      # set_url is a comma-separated list of env keys that should be populated
      # with the app's public URL (https://<app>.wokku.cloud). Ghost needs
      # `url=`, Plausible wants `BASE_URL=`, Strapi `APP_URL,ADMIN_URL`, etc.
      postgres_components: parse_components_prefix(metadata["postgres_components"], default: "DB_POSTGRESDB_"),
      mysql_components:    parse_components_prefix(metadata["mysql_components"],    default: nil),
      mongo_components:    parse_components_prefix(metadata["mongo_components"],    default: nil),
      set_url:             metadata["set_url"].to_s.split(",").map(&:strip).reject(&:blank?),
      # set_host: like set_url but the bare host (Nextcloud's NEXTCLOUD_TRUSTED_DOMAINS).
      set_host:            metadata["set_host"].to_s.split(",").map(&:strip).reject(&:blank?),
      # Comma-separated list of env keys that should be populated with
      # freshly generated random strings. Used for app-specific secrets
      # (APP_KEYS, JWT_SECRET, WEBUI_SECRET_KEY, HASURA_GRAPHQL_ADMIN_SECRET).
      generate_secrets:    metadata["generate_secrets"].to_s.split(",").map(&:strip).reject(&:blank?),
      # "TARGET=SOURCE,TARGET2=SOURCE2" — after provisioning, read SOURCE env
      # var from Dokku and set TARGET to the same value. Used for apps that
      # want a renamed URL (e.g. Hasura wants HASURA_GRAPHQL_DATABASE_URL,
      # but Dokku sets DATABASE_URL).
      alias_env:           parse_alias_env(metadata["alias_env"]),
      # Comma-separated list of in-container paths that need persistent
      # storage. Each path becomes a `dokku storage:mount` against a
      # host directory under /var/lib/dokku/data/storage/<app>/<basename>.
      # Example: `# storage_mounts: /app/data` for Uptime Kuma so its
      # monitor history survives redeploys.
      storage_mounts:      metadata["storage_mounts"].to_s.split(",").map(&:strip).reject(&:blank?),
      # Bundle v2 (backlog 4.7) — templates declare what they need from
      # the new addon model explicitly so the deployer routes through
      # Addons::SharedProvisioner (for shared) or the legacy DB-provision
      # path (for dedicated). Both default to "absent" so templates that
      # don't opt in stay on the existing `addons:` path.
      #
      #   shared_engines: postgres, redis      # auto-attach shared tenants
      #   dedicated_db_engine: mysql            # one dedicated DB container
      shared_engines:      parse_shared_engines(metadata["shared_engines"]),
      dedicated_db_engine: parse_dedicated_db_engine(metadata["dedicated_db_engine"]),
      # Forces a specific Dokku builder instead of letting Dokku auto-detect.
      # Apps whose repo ships a Dockerfile with required build steps (e.g.
      # Django `collectstatic` baking the WhiteNoise manifest) must set
      # `# builder: dockerfile` — otherwise Dokku detects herokuish, skips
      # those steps, and the app 500s (brightbean-studio, 2026-06-10). The
      # deployer also maps the proxy to container_port for these, since the
      # Dockerfile won't auto-bind $PORT the way herokuish does.
      builder:             parse_builder(metadata["builder"]),
      # Deploy-compatibility flags for images Dokku's defaults break:
      #   disable_init_process — Dokku runs containers with `--init` (tini as
      #     PID 1); s6-overlay images (`/init`) MUST be PID 1, else they exit
      #     with "s6-overlay-suexec: can only run as pid 1" (Hermes Agent).
      #   disable_zero_downtime_checks — the port-listening check nsenters the
      #     container PID ns and fails for multi-process (s6) trees on some hosts.
      disable_init_process:         parse_bool(metadata["disable_init_process"]),
      disable_zero_downtime_checks: parse_bool(metadata["disable_zero_downtime_checks"]),
      services: services
    }
  end

  def self.extract_metadata(yaml_content)
    metadata = {}
    yaml_content.each_line do |line|
      if (match = line.match(/\A#\s+(\w+):\s*(.+)/))
        metadata[match[1]] = match[2].strip
      end
    end
    metadata
  end

  def self.find_main_service(services)
    services.each do |name, config|
      image = config&.dig("image").to_s.split(":").first.to_s.split("/").last
      next if ADDON_IMAGES.key?(image)
      return [ name, config ]
    end
    services.first || [ nil, nil ]
  end

  def self.extract_addons(services, main_service_name)
    addons = []
    services.each do |name, config|
      next if name == main_service_name
      image = config&.dig("image").to_s.split(":").first.to_s.split("/").last
      addon_type = ADDON_IMAGES[image]
      # A pgvector-flavoured postgres addon maps to the basic-pgvector tier
      # (same caps/price as basic; the tier spec pins the pgvector image).
      tier = image == "pgvector" ? "basic-pgvector" : "basic"
      addons << { "type" => addon_type, "tier" => tier } if addon_type
    end
    addons.uniq { |a| a["type"] }
  end

  # "true"  → default prefix (backward compat for postgres_components: true)
  # "false" / nil → nil (feature off)
  # any other string → treated as the literal prefix (e.g. "database__connection__")
  def self.parse_alias_env(value)
    value.to_s.split(",").each_with_object({}) do |pair, h|
      target, source = pair.split("=", 2).map(&:strip)
      h[target] = source if target.present? && source.present?
    end
  end

  def self.parse_components_prefix(value, default:)
    str = value.to_s.strip
    return nil if str.empty? || str == "false"
    return default if str == "true"
    str
  end

  # Whitelist to the engines Addons::SharedProvisioner actually supports.
  # Unknown engines silently drop — keeping the contract narrow stops a
  # typo in a template manifest from spawning a meaningless DB tenant.
  SHARED_ENGINE_WHITELIST = DatabaseService::SHARED_ENGINES
  # redis: Sidekiq writes unprefixed keys, and shared-redis tenants are
  # ACL-locked to a key prefix (NOPERM, 2026-07-24) — job backends need a
  # dedicated redis.
  DEDICATED_DB_ENGINE_WHITELIST = %w[postgres mysql mariadb mongodb redis].freeze

  def self.parse_shared_engines(value)
    value.to_s.split(",").map(&:strip).select { |e| SHARED_ENGINE_WHITELIST.include?(e) }
  end

  def self.parse_dedicated_db_engine(value)
    str = value.to_s.strip
    DEDICATED_DB_ENGINE_WHITELIST.include?(str) ? str : nil
  end

  # Whitelist of Dokku builders we let a template select. Anything else
  # (typo, unsupported builder) falls back to nil so Dokku auto-detects —
  # a bad manifest can't feed an arbitrary value into `builder:set`.
  BUILDER_WHITELIST = %w[dockerfile herokuish pack].freeze

  def self.parse_builder(value)
    str = value.to_s.strip.downcase
    BUILDER_WHITELIST.include?(str) ? str : nil
  end

  def self.parse_bool(value)
    %w[true yes 1 on].include?(value.to_s.strip.downcase)
  end

  def self.extract_port(service)
    ports = service&.dig("ports")
    return nil unless ports&.any?
    port_str = ports.first.to_s
    port_str.include?(":") ? port_str.split(":").last.to_i : port_str.to_i
  end

  def self.healthcheck_from(metadata)
    cmd = metadata["healthcheck"].to_s.strip
    return nil if cmd.empty?

    start = metadata["healthcheck_start_period"].to_s[/\A\d+\z/]&.to_i || 90
    {
      "test" => [ "CMD-SHELL", cmd ],
      "interval_sec" => 10,
      "timeout_sec" => 5,
      "retries" => 5,
      "start_period_sec" => start
    }
  end

  private_class_method :find_main_service, :extract_addons, :extract_port, :parse_components_prefix, :parse_alias_env, :parse_shared_engines, :parse_dedicated_db_engine, :parse_builder, :healthcheck_from
end
