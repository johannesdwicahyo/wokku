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

  it "parses the main service's command, string or array form" do
    yaml = <<~YAML
      # port: 3000

      services:
        app:
          image: chatwoot/chatwoot:latest
          command: bundle exec rails s -p 3000 -b 0.0.0.0
    YAML
    expect(described_class.parse(yaml, slug: "x")[:command]).to eq("bundle exec rails s -p 3000 -b 0.0.0.0")

    yaml_array = <<~YAML
      services:
        app:
          image: x:1
          command: ["node", "server.js"]
    YAML
    expect(described_class.parse(yaml_array, slug: "x")[:command]).to eq("node server.js")
  end

  it "maps a pgvector image to a postgres addon on the basic-pgvector tier" do
    yaml = <<~YAML
      services:
        app:
          image: chatwoot/chatwoot:latest
        postgres:
          image: pgvector/pgvector:pg16
    YAML
    addons = described_class.parse(yaml, slug: "x")[:addons]
    expect(addons).to eq([ { "type" => "postgres", "tier" => "basic-pgvector" } ])
  end

  it "leaves command nil when the main service declares none" do
    yaml = <<~YAML
      services:
        app:
          image: x:1
    YAML
    expect(described_class.parse(yaml, slug: "x")[:command]).to be_nil
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

  it "set_host splits comma list" do
    yaml = "# set_host: NEXTCLOUD_TRUSTED_DOMAINS, HOST\nservices:\n  app:\n    image: foo\n"
    expect(described_class.parse(yaml, slug: "x")[:set_host]).to eq(%w[NEXTCLOUD_TRUSTED_DOMAINS HOST])
  end

  it "min_tier metadata is parsed when present" do
    yaml = "# min_tier: basic\nservices:\n  app:\n    image: foo\n"
    expect(described_class.parse(yaml, slug: "x")[:min_tier]).to eq("basic")
  end

  it "min_tier is nil when absent" do
    yaml = "services:\n  app:\n    image: foo\n"
    expect(described_class.parse(yaml, slug: "x")[:min_tier]).to be_nil
  end

  # Bundle v2 (backlog 4.7) — templates can declare shared addons + a
  # single dedicated DB explicitly so the deployer routes through
  # Addons::SharedProvisioner and the dedicated path rather than the
  # legacy `addons:` array (which provisions everything dedicated).
  describe "bundle v2 addon metadata" do
    it "shared_engines is a list parsed from comma-separated metadata" do
      yaml = "# shared_engines: postgres, redis\nservices:\n  app:\n    image: foo\n"
      expect(described_class.parse(yaml, slug: "x")[:shared_engines]).to eq(%w[postgres redis])
    end

    it "shared_engines defaults to [] when absent" do
      yaml = "services:\n  app:\n    image: foo\n"
      expect(described_class.parse(yaml, slug: "x")[:shared_engines]).to eq([])
    end

    it "dedicated_db_engine is the literal engine name" do
      yaml = "# dedicated_db_engine: mysql\nservices:\n  app:\n    image: foo\n"
      expect(described_class.parse(yaml, slug: "x")[:dedicated_db_engine]).to eq("mysql")
    end

    it "dedicated_db_engine is nil when absent" do
      yaml = "services:\n  app:\n    image: foo\n"
      expect(described_class.parse(yaml, slug: "x")[:dedicated_db_engine]).to be_nil
    end

    it "ignores unknown shared engines (whitelist)" do
      yaml = "# shared_engines: postgres, gophercloud, redis\nservices:\n  app:\n    image: foo\n"
      expect(described_class.parse(yaml, slug: "x")[:shared_engines]).to eq(%w[postgres redis])
    end

    it "ignores invalid dedicated_db_engine (whitelist)" do
      yaml = "# dedicated_db_engine: notreal\nservices:\n  app:\n    image: foo\n"
      expect(described_class.parse(yaml, slug: "x")[:dedicated_db_engine]).to be_nil
    end
  end

  # Templates whose repo relies on a Dockerfile build step (e.g. Django
  # collectstatic) must force the Dockerfile builder — Dokku otherwise
  # auto-detects herokuish and skips it, 500ing on the missing static
  # manifest (brightbean-studio, 2026-06-10).
  describe "builder metadata" do
    it "parses an explicit dockerfile builder" do
      yaml = "# builder: dockerfile\nservices:\n  app:\n    image: foo\n"
      expect(described_class.parse(yaml, slug: "x")[:builder]).to eq("dockerfile")
    end

    it "is nil when absent (Dokku auto-detects)" do
      yaml = "services:\n  app:\n    image: foo\n"
      expect(described_class.parse(yaml, slug: "x")[:builder]).to be_nil
    end

    it "ignores an unknown builder (whitelist)" do
      yaml = "# builder: magic\nservices:\n  app:\n    image: foo\n"
      expect(described_class.parse(yaml, slug: "x")[:builder]).to be_nil
    end
  end

  # wokkud already translates a "healthcheck" key on converge service specs
  # into a Swarm container healthcheck. Swarm start-first counts a task
  # healthy the instant it Runs, so slow-boot images (ghost/umami ~60s) blip
  # on every rollout without one. TemplateParser is the single source of
  # defaults — the deployer/converge layers pass the hash through verbatim.
  describe "healthcheck metadata" do
    def parse_with(comment_lines)
      yaml = <<~YAML
        # name: HC Test
        # port: 3000
        #{comment_lines}
        services:
          app:
            image: nginx:latest
      YAML
      described_class.parse(yaml, slug: "hc-test")
    end

    it "builds the full agent-shaped hash with defaults" do
      t = parse_with("# healthcheck: curl -fsS http://127.0.0.1:3000/ || exit 1")
      expect(t[:healthcheck]).to eq(
        "test" => [ "CMD-SHELL", "curl -fsS http://127.0.0.1:3000/ || exit 1" ],
        "interval_sec" => 10, "timeout_sec" => 5, "retries" => 5, "start_period_sec" => 90
      )
    end

    it "honors healthcheck_start_period" do
      t = parse_with("# healthcheck: curl -f localhost:3000\n# healthcheck_start_period: 120")
      expect(t[:healthcheck]["start_period_sec"]).to eq(120)
    end

    it "is nil when the key is absent" do
      expect(parse_with("")[:healthcheck]).to be_nil
    end

    it "ignores a garbage start period (falls back to 90)" do
      t = parse_with("# healthcheck: curl -f localhost:3000\n# healthcheck_start_period: soon")
      expect(t[:healthcheck]["start_period_sec"]).to eq(90)
    end

    it "parses ghost template's node-based healthcheck (no curl/wget available)" do
      yaml_path = Wokku::Engine.root.join("app/templates/ghost/docker-compose.yml")
      t = described_class.parse(File.read(yaml_path), slug: "ghost")
      expect(t[:healthcheck]).to be_present
      expect(t[:healthcheck]["test"]).to eq(
        [ "CMD-SHELL", "node -e \"require('http').get('http://127.0.0.1:'+process.env.PORT+'/',r=>process.exit(r.statusCode<500?0:1)).on('error',()=>process.exit(1))\"" ]
      )
      expect(t[:healthcheck]["start_period_sec"]).to eq(90)
    end

    it "parses umami template's curl-based healthcheck" do
      yaml_path = Wokku::Engine.root.join("app/templates/umami/docker-compose.yml")
      t = described_class.parse(File.read(yaml_path), slug: "umami")
      expect(t[:healthcheck]).to be_present
      expect(t[:healthcheck]["test"]).to eq(
        [ "CMD-SHELL", "curl -fsS http://127.0.0.1:$PORT/api/heartbeat || exit 1" ]
      )
      expect(t[:healthcheck]["start_period_sec"]).to eq(90)
    end
  end
end
