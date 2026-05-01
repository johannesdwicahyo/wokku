require "test_helper"

class TemplateRegistryTest < ActiveSupport::TestCase
  test "loads templates from JSON files" do
    registry = TemplateRegistry.new
    templates = registry.all
    assert templates.any?
    assert templates.first[:name].present?
  end

  test "finds template by slug" do
    registry = TemplateRegistry.new
    template = registry.find("rails-tailwind")
    assert_equal "Rails + Tailwind", template[:name]
    assert_equal "postgres", template[:addons].first["type"]
  end

  test "returns nil for unknown slug" do
    registry = TemplateRegistry.new
    assert_nil registry.find("nonexistent")
  end

  test "filters by category" do
    registry = TemplateRegistry.new
    frameworks = registry.by_category("frameworks")
    assert frameworks.all? { |t| t[:category] == "frameworks" }
  end

  test "searches by name and tags" do
    registry = TemplateRegistry.new
    results = registry.search("rails")
    assert results.any? { |t| t[:slug] == "rails-tailwind" }
  end

  test "returns categories" do
    registry = TemplateRegistry.new
    cats = registry.categories
    assert cats.any? { |c| c["slug"] == "frameworks" }
  end
end
