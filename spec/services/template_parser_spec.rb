# frozen_string_literal: true

require "rails_helper"

RSpec.describe TemplateParser do
  it "parses metadata from YAML comments" do
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

    template = described_class.parse(yaml, slug: "n8n")
    expect(template[:description]).to eq("Workflow automation tool")
    expect(template[:category]).to eq("automation")
    expect(template[:tags]).to eq([ "automation", "workflow", "node" ])
    expect(template[:container_port]).to eq(5678)
    expect(template[:docker_image]).to eq("n8nio/n8n:latest")
    expect(template[:deploy_method]).to eq("docker_image")
    expect(template[:addons]).to eq([ { "type" => "postgres", "tier" => "basic" } ])
  end

  it "parses template with no database services" do
    yaml = <<~YAML
      # slogan: Simple uptime monitor
      # category: devtools
      # tags: monitoring, uptime
      # port: 3001

      services:
        uptime-kuma:
          image: louislam/uptime-kuma:latest
    YAML

    template = described_class.parse(yaml, slug: "uptime-kuma")
    expect(template[:docker_image]).to eq("louislam/uptime-kuma:latest")
    expect(template[:addons]).to be_empty
  end

  it "identifies database services as addons" do
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

    template = described_class.parse(yaml, slug: "test")
    expect(template[:addons].size).to eq(2)
    expect(template[:addons].any? { |a| a["type"] == "postgres" }).to be_truthy
    expect(template[:addons].any? { |a| a["type"] == "redis" }).to be_truthy
  end

  it "postgres_components: true uses the n8n-default prefix" do
    yaml = "# postgres_components: true\nservices:\n  app:\n    image: foo\n"
    expect(described_class.parse(yaml, slug: "x")[:postgres_components]).to eq("DB_POSTGRESDB_")
  end

  it "postgres_components absent returns nil (no expansion)" do
    yaml = "services:\n  app:\n    image: foo\n"
    expect(described_class.parse(yaml, slug: "x")[:postgres_components]).to be_nil
  end

  it "mysql_components accepts a custom prefix (Ghost convention)" do
    yaml = "# mysql_components: database__connection__\nservices:\n  app:\n    image: foo\n"
    expect(described_class.parse(yaml, slug: "x")[:mysql_components]).to eq("database__connection__")
  end

  it "set_url splits comma list and strips whitespace" do
    yaml = "# set_url: url, BASE_URL ,APP_URL\nservices:\n  app:\n    image: foo\n"
    expect(described_class.parse(yaml, slug: "x")[:set_url]).to eq(%w[url BASE_URL APP_URL])
  end

  it "set_url defaults to empty array when absent" do
    yaml = "services:\n  app:\n    image: foo\n"
    expect(described_class.parse(yaml, slug: "x")[:set_url]).to eq([])
  end

  it "min_tier metadata is parsed when present" do
    yaml = "# min_tier: basic\nservices:\n  app:\n    image: foo\n"
    expect(described_class.parse(yaml, slug: "x")[:min_tier]).to eq("basic")
  end

  it "min_tier is nil when absent" do
    yaml = "services:\n  app:\n    image: foo\n"
    expect(described_class.parse(yaml, slug: "x")[:min_tier]).to be_nil
  end
end
