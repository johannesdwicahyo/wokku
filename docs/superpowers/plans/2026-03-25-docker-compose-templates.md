# Docker Compose Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the template system to Docker Compose YAML format (Coolify-compatible), enabling multi-service app definitions, community contributions via standard compose files, and import of 300+ templates from Coolify/Dokploy.

**Architecture:** The TemplateRegistry is updated to load both `template.json` (legacy) and `docker-compose.yml` (new format) files. YAML templates use metadata comments for name, description, category, tags, and icon. The TemplateDeployer already handles Docker images and addons — the YAML parser extracts the main service image and maps `depends_on` services to Dokku addons. A migration script converts all 51 JSON templates to YAML. An import script pulls templates from Coolify's GitHub repo.

**Tech Stack:** Ruby YAML parser, Docker Compose YAML format, existing TemplateRegistry/TemplateDeployer

---

## File Structure

### New Files

```
app/services/template_parser.rb                     — Parse Docker Compose YAML with metadata comments
lib/tasks/templates.rake                             — Rake tasks: convert JSON→YAML, import from Coolify
test/services/template_parser_test.rb
```

### Modified Files

```
app/services/template_registry.rb                    — Load YAML templates alongside JSON (backward-compat)
app/services/template_deployer.rb                    — Minor: handle :services key from YAML templates
app/templates/*/docker-compose.yml                   — 51 new YAML files (replacing template.json)
```

---

## Task 1: TemplateParser Service

**Files:**
- Create: `app/services/template_parser.rb`
- Create: `test/services/template_parser_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/services/template_parser_test.rb
require "test_helper"

class TemplateParserTest < ActiveSupport::TestCase
  test "parses metadata from YAML comments" do
    yaml = <<~YAML
      # documentation: https://n8n.io
      # slogan: Workflow automation tool
      # category: automation
      # tags: automation, workflow, node
      # icon: automation
      # port: 5678

      services:
        n8n:
          image: n8nio/n8n:latest
          environment:
            - DB_TYPE=postgresdb
        postgres:
          image: postgres:16
          volumes:
            - pg-data:/var/lib/postgresql/data
      volumes:
        pg-data:
    YAML

    template = TemplateParser.parse(yaml, slug: "n8n")

    assert_equal "Workflow automation tool", template[:description]
    assert_equal "automation", template[:category]
    assert_equal ["automation", "workflow", "node"], template[:tags]
    assert_equal "automation", template[:icon]
    assert_equal 5678, template[:container_port]
    assert_equal "n8nio/n8n:latest", template[:docker_image]
    assert_equal "docker_image", template[:deploy_method]
    assert_equal [{"type" => "postgres", "tier" => "mini"}], template[:addons]
  end

  test "parses template with no database services" do
    yaml = <<~YAML
      # slogan: Simple uptime monitor
      # category: devtools
      # tags: monitoring, uptime
      # icon: monitor
      # port: 3001

      services:
        uptime-kuma:
          image: louislam/uptime-kuma:latest
    YAML

    template = TemplateParser.parse(yaml, slug: "uptime-kuma")
    assert_equal "louislam/uptime-kuma:latest", template[:docker_image]
    assert_empty template[:addons]
  end

  test "extracts name from slug if no slogan" do
    yaml = <<~YAML
      services:
        myapp:
          image: myapp:latest
    YAML

    template = TemplateParser.parse(yaml, slug: "my-cool-app")
    assert_equal "My Cool App", template[:name]
  end

  test "identifies database services as addons" do
    yaml = <<~YAML
      # slogan: Test app
      # category: frameworks
      # tags: test
      # icon: node
      # port: 3000

      services:
        app:
          image: myapp:latest
          depends_on:
            - postgres
            - redis
        postgres:
          image: postgres:16
        redis:
          image: redis:7
    YAML

    template = TemplateParser.parse(yaml, slug: "test")
    addons = template[:addons]
    assert_equal 2, addons.size
    assert addons.any? { |a| a["type"] == "postgres" }
    assert addons.any? { |a| a["type"] == "redis" }
  end
end
```

- [ ] **Step 2: Write the service**

```ruby
# app/services/template_parser.rb
class TemplateParser
  # Database images that map to Dokku addons
  ADDON_IMAGES = {
    "postgres" => "postgres",
    "postgresql" => "postgres",
    "mysql" => "mysql",
    "mariadb" => "mariadb",
    "redis" => "redis",
    "mongo" => "mongodb",
    "mongodb" => "mongodb",
    "memcached" => "memcached",
    "rabbitmq" => "rabbitmq",
    "elasticsearch" => "elasticsearch",
    "minio" => "minio"
  }.freeze

  def self.parse(yaml_content, slug:)
    metadata = extract_metadata(yaml_content)
    compose = YAML.safe_load(yaml_content, permitted_classes: [Symbol]) || {}
    services = compose["services"] || {}

    # Identify main service (first non-database service)
    main_service_name, main_service = find_main_service(services)
    addons = extract_addons(services, main_service_name)

    # Extract image and port
    image = main_service&.dig("image")
    port = metadata["port"]&.to_i || extract_port(main_service)

    # Build environment variables
    env = {}
    (main_service&.dig("environment") || []).each do |e|
      if e.is_a?(String) && e.include?("=")
        key, value = e.split("=", 2)
        env[key] = value unless value&.start_with?("${")
      end
    end

    {
      name: metadata["slogan"] || slug.tr("-", " ").titleize,
      slug: slug,
      description: metadata["slogan"] || "",
      category: metadata["category"] || "uncategorized",
      icon: metadata["icon"] || guess_icon(slug),
      repo: metadata["documentation"] || "",
      branch: "main",
      tags: (metadata["tags"] || "").split(",").map(&:strip),
      deploy_method: image ? "docker_image" : "git",
      docker_image: image&.sub(/:latest$/, "")&.then { |i| i.include?(":") ? image : i },
      container_port: port,
      addons: addons,
      env: env,
      post_deploy: metadata["post_deploy"] || "",
      services: services  # Keep raw compose services for advanced use
    }
  end

  def self.extract_metadata(yaml_content)
    metadata = {}
    yaml_content.each_line do |line|
      if line.match?(/\A#\s+\w+:/)
        match = line.match(/\A#\s+(\w+):\s*(.+)/)
        metadata[match[1]] = match[2].strip if match
      end
    end
    metadata
  end

  def self.find_main_service(services)
    # Main service = first service that is NOT a known database
    services.each do |name, config|
      image = config&.dig("image").to_s.split(":").first.to_s.split("/").last
      next if ADDON_IMAGES.key?(image)
      return [name, config]
    end
    # Fallback: first service
    services.first || [nil, nil]
  end

  def self.extract_addons(services, main_service_name)
    addons = []
    services.each do |name, config|
      next if name == main_service_name
      image = config&.dig("image").to_s.split(":").first.to_s.split("/").last
      addon_type = ADDON_IMAGES[image]
      if addon_type
        addons << { "type" => addon_type, "tier" => "mini" }
      end
    end
    addons.uniq { |a| a["type"] }
  end

  def self.extract_port(service)
    ports = service&.dig("ports")
    return nil unless ports&.any?
    # Parse "8080:3000" or "3000"
    port_str = ports.first.to_s
    port_str.include?(":") ? port_str.split(":").last.to_i : port_str.to_i
  end

  def self.guess_icon(slug)
    icons = {
      "rails" => "rails", "django" => "python", "flask" => "python",
      "express" => "node", "next" => "node", "nuxt" => "node",
      "laravel" => "php", "wordpress" => "php", "ghost" => "cms",
      "grafana" => "monitor", "prometheus" => "monitor"
    }
    icons.find { |k, _| slug.include?(k) }&.last || "docker"
  end

  private_class_method :find_main_service, :extract_addons, :extract_port, :guess_icon
end
```

- [ ] **Step 3: Run tests**

Run: `bin/rails test test/services/template_parser_test.rb`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add app/services/template_parser.rb test/services/template_parser_test.rb
git commit -m "feat: add TemplateParser for Docker Compose YAML templates"
```

---

## Task 2: Update TemplateRegistry to Support Both Formats

**Files:**
- Modify: `app/services/template_registry.rb`

- [ ] **Step 1: Update load_templates to support YAML**

Read the file first. Replace the `load_templates` private method with:

```ruby
  def load_templates
    templates = []

    Dir[TEMPLATES_PATH.join("*/")].each do |dir|
      slug = File.basename(dir)
      yaml_path = File.join(dir, "docker-compose.yml")
      json_path = File.join(dir, "template.json")

      template = if File.exist?(yaml_path)
        TemplateParser.parse(File.read(yaml_path), slug: slug)
      elsif File.exist?(json_path)
        data = JSON.parse(File.read(json_path))
        data.symbolize_keys.merge(slug: slug)
      end

      templates << template if template
    rescue => e
      Rails.logger.warn("Failed to parse template in #{dir}: #{e.message}")
    end

    templates.sort_by { |t| t[:name] }
  end
```

This keeps backward compatibility — JSON templates continue to work, YAML templates are preferred when both exist.

- [ ] **Step 2: Commit**

```bash
git add app/services/template_registry.rb
git commit -m "feat: TemplateRegistry now loads Docker Compose YAML templates (backward-compat)"
```

---

## Task 3: Rake Task for JSON → YAML Conversion

**Files:**
- Create: `lib/tasks/templates.rake`

- [ ] **Step 1: Write the rake task**

```ruby
# lib/tasks/templates.rake
namespace :templates do
  desc "Convert all JSON templates to Docker Compose YAML format"
  task convert: :environment do
    templates_path = Rails.root.join("app/templates")

    Dir[templates_path.join("*/template.json")].each do |json_path|
      dir = File.dirname(json_path)
      slug = File.basename(dir)
      yaml_path = File.join(dir, "docker-compose.yml")

      # Skip if YAML already exists
      if File.exist?(yaml_path)
        puts "  SKIP #{slug} (docker-compose.yml already exists)"
        next
      end

      data = JSON.parse(File.read(json_path))
      yaml_content = build_compose_yaml(data, slug)

      File.write(yaml_path, yaml_content)
      puts "  CONVERTED #{slug}"
    end

    puts "\nDone! YAML templates created. You can delete template.json files after verifying."
  end

  desc "Import templates from Coolify's GitHub repository"
  task import_coolify: :environment do
    require "open-uri"
    require "json"

    puts "Fetching Coolify template list..."
    # Coolify templates are in /templates/compose/ directory
    api_url = "https://api.github.com/repos/coollabsio/coolify/contents/templates/compose"
    response = URI.open(api_url, "Accept" => "application/vnd.github.v3+json").read
    entries = JSON.parse(response)

    templates_path = Rails.root.join("app/templates")
    imported = 0

    entries.select { |e| e["type"] == "file" && e["name"].end_with?(".yaml") }.each do |entry|
      slug = entry["name"].delete_suffix(".yaml")
      target_dir = templates_path.join(slug)

      # Skip if already exists
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

  # Metadata comments
  lines << "# documentation: #{data['repo']}" if data["repo"].present?
  lines << "# slogan: #{data['description']}" if data["description"].present?
  lines << "# category: #{data['category']}" if data["category"].present?
  lines << "# tags: #{data['tags'].join(', ')}" if data["tags"]&.any?
  lines << "# icon: #{data['icon']}" if data["icon"].present?
  lines << "# port: #{data['container_port']}" if data["container_port"]
  lines << "# post_deploy: #{data['post_deploy']}" if data["post_deploy"].present?
  lines << ""

  # Services section
  lines << "services:"

  # Main service
  service_name = slug.gsub("-", "_")
  lines << "  #{service_name}:"

  if data["deploy_method"] == "docker_image" && data["docker_image"]
    lines << "    image: #{data['docker_image']}:latest"
  elsif data["repo"]
    lines << "    build:"
    lines << "      context: #{data['repo']}"
  end

  # Environment variables
  if data["env"]&.any?
    lines << "    environment:"
    data["env"].each do |key, value|
      lines << "      - #{key}=#{value}"
    end
  end

  # Ports
  if data["container_port"]
    lines << "    ports:"
    lines << "      - \"#{data['container_port']}:#{data['container_port']}\""
  end

  # Database dependencies
  if data["addons"]&.any?
    lines << "    depends_on:"
    data["addons"].each { |a| lines << "      - #{a['type']}" }
    lines << ""

    # Database services
    data["addons"].each do |addon|
      type = addon["type"]
      image = case type
        when "postgres" then "postgres:16"
        when "redis" then "redis:7"
        when "mysql" then "mysql:8"
        when "mariadb" then "mariadb:11"
        when "mongodb" then "mongo:7"
        when "elasticsearch" then "elasticsearch:8"
        else "#{type}:latest"
      end
      lines << "  #{type}:"
      lines << "    image: #{image}"
      if %w[postgres mysql mariadb].include?(type)
        lines << "    volumes:"
        lines << "      - #{type}-data:/var/lib/#{type == 'postgres' ? 'postgresql' : type}/data"
      end
    end
  end

  # Volumes
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
```

- [ ] **Step 2: Commit**

```bash
git add lib/tasks/templates.rake
git commit -m "feat: add rake tasks for JSON→YAML conversion and Coolify template import"
```

---

## Task 4: Convert All 51 Templates to YAML

**Files:**
- Create: 51 `docker-compose.yml` files in `app/templates/*/`

- [ ] **Step 1: Run the conversion rake task locally**

This step can be simulated by a subagent: for each existing `app/templates/*/template.json`, create a corresponding `docker-compose.yml` using the format:

```yaml
# documentation: <repo url>
# slogan: <description>
# category: <category>
# tags: <comma-separated tags>
# icon: <icon>
# port: <container_port>
# post_deploy: <post_deploy command>

services:
  <slug>:
    image: <docker_image>:latest
    environment:
      - KEY=VALUE
    ports:
      - "<port>:<port>"
    depends_on:
      - postgres
  postgres:
    image: postgres:16
    volumes:
      - postgres-data:/var/lib/postgresql/data

volumes:
  postgres-data:
```

Create YAML files for ALL 51 templates. The JSON files can remain for backward compatibility.

- [ ] **Step 2: Verify templates load correctly**

After creating YAML files, the TemplateRegistry should prefer YAML over JSON. Verify by checking template count hasn't changed.

- [ ] **Step 3: Commit**

```bash
git add app/templates/*/docker-compose.yml
git commit -m "feat: convert all 51 templates to Docker Compose YAML format"
```

---

## Task 5: Delete Legacy JSON Templates

**Files:**
- Delete: 51 `app/templates/*/template.json` files

- [ ] **Step 1: Remove JSON files**

After verifying YAML templates work, delete all `template.json` files:

```bash
find app/templates -name "template.json" -delete
```

- [ ] **Step 2: Commit**

```bash
git add -u app/templates/
git commit -m "chore: remove legacy JSON templates (replaced by Docker Compose YAML)"
```

---

## Summary

| Task | Component | New Files | Modified Files |
|---|---|---|---|
| 1 | TemplateParser service | 2 | 0 |
| 2 | TemplateRegistry YAML support | 0 | 1 |
| 3 | Rake tasks (convert + import) | 1 | 0 |
| 4 | Convert 51 templates to YAML | 51 | 0 |
| 5 | Delete legacy JSON templates | 0 (51 deleted) | 0 |

**Total: 54 new files, 1 modified file, 51 deleted files, 5 tasks**

## Post-Migration: Import Coolify Templates

After this plan is executed, run:
```bash
bin/rails templates:import_coolify
```

This will import ~300 additional templates from Coolify's GitHub repo, instantly expanding the Wokku marketplace.
