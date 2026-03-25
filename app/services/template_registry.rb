class TemplateRegistry
  TEMPLATES_PATH = Rails.root.join("app/templates")

  def initialize
    @templates = load_templates
    @registry = load_registry
  end

  def all
    @templates
  end

  def find(slug)
    @templates.find { |t| t[:slug] == slug }
  end

  def by_category(category)
    @templates.select { |t| t[:category] == category }
  end

  def search(query)
    q = query.to_s.downcase
    @templates.select do |t|
      t[:name].downcase.include?(q) ||
        t[:description].to_s.downcase.include?(q) ||
        t[:tags].any? { |tag| tag.downcase.include?(q) }
    end
  end

  def categories
    @registry["categories"] || []
  end

  private

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

  def load_registry
    path = TEMPLATES_PATH.join("registry.yml")
    path.exist? ? YAML.load_file(path) : {}
  end
end
