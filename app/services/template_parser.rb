class TemplateParser
  ADDON_IMAGES = {
    "postgres" => "postgres", "postgresql" => "postgres",
    "mysql" => "mysql", "mariadb" => "mariadb",
    "redis" => "redis", "mongo" => "mongodb", "mongodb" => "mongodb",
    "memcached" => "memcached", "rabbitmq" => "rabbitmq",
    "elasticsearch" => "elasticsearch", "minio" => "minio"
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
      repo: metadata["documentation"] || "",
      branch: "main",
      tags: (metadata["tags"] || "").split(",").map(&:strip),
      deploy_method: image ? "docker_image" : "git",
      docker_image: image,
      container_port: port,
      addons: addons,
      env: env,
      post_deploy: metadata["post_deploy"] || "",
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
      # Comma-separated list of env keys that should be populated with
      # freshly generated random strings. Used for app-specific secrets
      # (APP_KEYS, JWT_SECRET, WEBUI_SECRET_KEY, HASURA_GRAPHQL_ADMIN_SECRET).
      generate_secrets:    metadata["generate_secrets"].to_s.split(",").map(&:strip).reject(&:blank?),
      # "TARGET=SOURCE,TARGET2=SOURCE2" — after provisioning, read SOURCE env
      # var from Dokku and set TARGET to the same value. Used for apps that
      # want a renamed URL (e.g. Hasura wants HASURA_GRAPHQL_DATABASE_URL,
      # but Dokku sets DATABASE_URL).
      alias_env:           parse_alias_env(metadata["alias_env"]),
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
      addons << { "type" => addon_type, "tier" => "mini" } if addon_type
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

  def self.extract_port(service)
    ports = service&.dig("ports")
    return nil unless ports&.any?
    port_str = ports.first.to_s
    port_str.include?(":") ? port_str.split(":").last.to_i : port_str.to_i
  end

  private_class_method :find_main_service, :extract_addons, :extract_port, :parse_components_prefix, :parse_alias_env
end
