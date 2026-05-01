namespace :templates do
  desc "Convert all JSON templates to Docker Compose YAML format"
  task convert: :environment do
    templates_path = Rails.root.join("app/templates")

    Dir[templates_path.join("*/template.json")].each do |json_path|
      dir = File.dirname(json_path)
      slug = File.basename(dir)
      yaml_path = File.join(dir, "docker-compose.yml")

      if File.exist?(yaml_path)
        puts "  SKIP #{slug} (docker-compose.yml already exists)"
        next
      end

      data = JSON.parse(File.read(json_path))
      yaml_content = build_compose_yaml(data, slug)

      File.write(yaml_path, yaml_content)
      puts "  CONVERTED #{slug}"
    end

    puts "\nDone! YAML templates created."
  end

  desc "Import templates from Coolify's GitHub repository"
  task import_coolify: :environment do
    require "open-uri"
    require "json"

    puts "Fetching Coolify template list..."
    api_url = "https://api.github.com/repos/coollabsio/coolify/contents/templates/compose"
    response = URI.open(api_url, "Accept" => "application/vnd.github.v3+json").read
    entries = JSON.parse(response)

    templates_path = Rails.root.join("app/templates")
    imported = 0

    entries.select { |e| e["type"] == "file" && e["name"].end_with?(".yaml") }.each do |entry|
      slug = entry["name"].delete_suffix(".yaml")
      target_dir = templates_path.join(slug)

      if target_dir.exist?
        puts "  SKIP #{slug} (already exists)"
        next
      end

      begin
        yaml_content = URI.open(entry["download_url"]).read
        FileUtils.mkdir_p(target_dir)
        File.write(target_dir.join("docker-compose.yml"), yaml_content)
        puts "  IMPORTED #{slug}"
        imported += 1
      rescue OpenURI::HTTPError => e
        puts "  FAILED #{slug}: #{e.message}"
      end
    end

    puts "\nImported #{imported} templates from Coolify."
  end
end

def build_compose_yaml(data, slug)
  lines = []

  lines << "# documentation: #{data['repo']}" if data["repo"].present?
  lines << "# slogan: #{data['description']}" if data["description"].present?
  lines << "# category: #{data['category']}" if data["category"].present?
  lines << "# tags: #{data['tags'].join(', ')}" if data["tags"]&.any?
  lines << "# icon: #{data['icon']}" if data["icon"].present?
  lines << "# port: #{data['container_port']}" if data["container_port"]
  lines << "# post_deploy: #{data['post_deploy']}" if data["post_deploy"].present?
  lines << ""
  lines << "services:"

  service_name = slug.tr("-", "_")
  lines << "  #{service_name}:"

  if data["deploy_method"] == "docker_image" && data["docker_image"]
    lines << "    image: #{data['docker_image']}:latest"
  elsif data["repo"]
    lines << "    image: #{slug}:latest"
  end

  if data["env"]&.any?
    lines << "    environment:"
    data["env"].each { |key, value| lines << "      - #{key}=#{value}" }
  end

  if data["container_port"]
    lines << "    ports:"
    lines << "      - \"#{data['container_port']}:#{data['container_port']}\""
  end

  if data["addons"]&.any?
    lines << "    depends_on:"
    data["addons"].each { |a| lines << "      - #{a['type']}" }
    lines << ""

    data["addons"].each do |addon|
      type = addon["type"]
      image = case type
      when "postgres" then "postgres:16"
      when "redis" then "redis:7"
      when "mysql" then "mysql:8"
      when "mariadb" then "mariadb:11"
      when "mongodb" then "mongo:7"
      else "#{type}:latest"
      end
      lines << "  #{type}:"
      lines << "    image: #{image}"
      if %w[postgres mysql mariadb].include?(type)
        lines << "    volumes:"
        db_path = type == "postgres" ? "postgresql" : type
        lines << "      - #{type}-data:/var/lib/#{db_path}/data"
      end
    end
  end

  if data["addons"]&.any? { |a| %w[postgres mysql mariadb].include?(a["type"]) }
    lines << ""
    lines << "volumes:"
    data["addons"].each do |addon|
      if %w[postgres mysql mariadb].include?(addon["type"])
        lines << "  #{addon['type']}-data:"
      end
    end
  end

  lines.join("\n") + "\n"
end
