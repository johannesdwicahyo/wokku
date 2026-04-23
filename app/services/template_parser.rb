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
      # Apps like n8n don't accept DATABASE_URL — they expect individual
      # DB_POSTGRESDB_HOST/PORT/DATABASE/USER/PASSWORD vars. When the
      # template sets `# postgres_components: true`, the deployer will
      # parse the DATABASE_URL set by Dokku's postgres addon and write
      # those 5 vars after linking.
      postgres_components: metadata["postgres_components"].to_s == "true",
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

  def self.extract_port(service)
    ports = service&.dig("ports")
    return nil unless ports&.any?
    port_str = ports.first.to_s
    port_str.include?(":") ? port_str.split(":").last.to_i : port_str.to_i
  end

  private_class_method :find_main_service, :extract_addons, :extract_port
end
