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
    Dir[TEMPLATES_PATH.join("*/template.json")].filter_map do |path|
      data = JSON.parse(File.read(path))
      data.symbolize_keys.merge(slug: File.basename(File.dirname(path)))
    rescue JSON::ParserError => e
      Rails.logger.warn("Failed to parse template: #{path} — #{e.message}")
      nil
    end.sort_by { |t| t[:name] }
  end

  def load_registry
    path = TEMPLATES_PATH.join("registry.yml")
    path.exist? ? YAML.load_file(path) : {}
  end
end
