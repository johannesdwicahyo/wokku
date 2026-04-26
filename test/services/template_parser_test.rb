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
    assert_equal [ { "type" => "postgres", "tier" => "basic" } ], template[:addons]
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

  test "postgres_components: true uses the n8n-default prefix" do
    yaml = "# postgres_components: true\nservices:\n  app:\n    image: foo\n"
    assert_equal "DB_POSTGRESDB_", TemplateParser.parse(yaml, slug: "x")[:postgres_components]
  end

  test "postgres_components absent returns nil (no expansion)" do
    yaml = "services:\n  app:\n    image: foo\n"
    assert_nil TemplateParser.parse(yaml, slug: "x")[:postgres_components]
  end

  test "mysql_components accepts a custom prefix (Ghost convention)" do
    yaml = "# mysql_components: database__connection__\nservices:\n  app:\n    image: foo\n"
    assert_equal "database__connection__", TemplateParser.parse(yaml, slug: "x")[:mysql_components]
  end

  test "set_url splits comma list and strips whitespace" do
    yaml = "# set_url: url, BASE_URL ,APP_URL\nservices:\n  app:\n    image: foo\n"
    assert_equal %w[url BASE_URL APP_URL], TemplateParser.parse(yaml, slug: "x")[:set_url]
  end

  test "set_url defaults to empty array when absent" do
    yaml = "services:\n  app:\n    image: foo\n"
    assert_equal [], TemplateParser.parse(yaml, slug: "x")[:set_url]
  end
end
