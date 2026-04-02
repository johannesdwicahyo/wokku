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
    YAML

    template = TemplateParser.parse(yaml, slug: "n8n")
    assert_equal "Workflow automation tool", template[:description]
    assert_equal "automation", template[:category]
    assert_equal [ "automation", "workflow", "node" ], template[:tags]
    assert_equal 5678, template[:container_port]
    assert_equal "n8nio/n8n:latest", template[:docker_image]
    assert_equal "docker_image", template[:deploy_method]
    assert_equal [ { "type" => "postgres", "tier" => "mini" } ], template[:addons]
  end

  test "parses template with no database services" do
    yaml = <<~YAML
      # slogan: Simple uptime monitor
      # category: devtools
      # tags: monitoring, uptime
      # port: 3001

      services:
        uptime-kuma:
          image: louislam/uptime-kuma:latest
    YAML

    template = TemplateParser.parse(yaml, slug: "uptime-kuma")
    assert_equal "louislam/uptime-kuma:latest", template[:docker_image]
    assert_empty template[:addons]
  end

  test "identifies database services as addons" do
    yaml = <<~YAML
      # slogan: Test app
      # category: frameworks
      # tags: test
      # port: 3000

      services:
        app:
          image: myapp:latest
        postgres:
          image: postgres:16
        redis:
          image: redis:7
    YAML

    template = TemplateParser.parse(yaml, slug: "test")
    assert_equal 2, template[:addons].size
    assert template[:addons].any? { |a| a["type"] == "postgres" }
    assert template[:addons].any? { |a| a["type"] == "redis" }
  end
end
