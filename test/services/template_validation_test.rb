require "test_helper"

class TemplateValidationTest < ActiveSupport::TestCase
  test "all templates have required fields" do
    registry = TemplateRegistry.new
    registry.all.each do |template|
      assert template[:name].present?, "#{template[:slug]} missing name"
      assert template[:slug].present?, "template missing slug"
      assert template[:category].present?, "#{template[:slug]} missing category"
    end
  end

  test "all templates have docker-compose.yml" do
    registry = TemplateRegistry.new
    registry.all.each do |template|
      path = Rails.root.join("app/templates", template[:slug], "docker-compose.yml")
      assert File.exist?(path), "#{template[:slug]} missing docker-compose.yml"
    end
  end

  test "all template compose files reference an image" do
    registry = TemplateRegistry.new
    registry.all.each do |template|
      path = Rails.root.join("app/templates", template[:slug], "docker-compose.yml")
      next unless File.exist?(path)
      content = File.read(path)
      assert content.include?("image:"), "#{template[:slug]} has no image reference"
    end
  end
end
