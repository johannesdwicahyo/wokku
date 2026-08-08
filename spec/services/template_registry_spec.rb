# frozen_string_literal: true

require "rails_helper"

RSpec.describe TemplateRegistry do
  let(:registry) { described_class.new }

  it "loads templates from JSON files" do
    templates = registry.all
    expect(templates).to be_any
    expect(templates.first[:name]).to be_present
  end

  it "finds template by slug" do
    template = registry.find("chatwoot")
    expect(template[:name]).to eq("Chatwoot")
    expect(template[:addons].first["type"]).to eq("postgres")
  end

  it "returns nil for unknown slug" do
    expect(registry.find("nonexistent")).to be_nil
  end

  it "filters by category" do
    frameworks = registry.by_category("frameworks")
    expect(frameworks.all? { |t| t[:category] == "frameworks" }).to be_truthy
  end

  it "searches by name and tags" do
    results = registry.search("rails")
    expect(results.any? { |t| t[:slug] == "rails" }).to be_truthy
  end

  it "returns categories" do
    cats = registry.categories
    expect(cats.any? { |c| c["slug"] == "frameworks" }).to be_truthy
  end

  it "ships the Hermes Agent template wired for its adapted-image deploy" do
    t = registry.find("hermes-agent")
    expect(t[:name]).to eq("Hermes Agent")
    expect(t[:category]).to eq("ai")
    expect(t[:repo]).to eq("https://github.com/johannesdwicahyo/wokku-hermes-agent")
    expect(t[:deploy_method]).to eq("git")     # built from the repo, no published image
    expect(t[:builder]).to eq("dockerfile")    # repo ships a Dockerfile
    expect(t[:container_port]).to eq(9119)
    expect(t[:min_tier]).to eq("standard")     # Medium (1 GB) minimum
    expect(t[:storage_mounts]).to include("/opt/data")
    # s6-overlay deploy-compat flags (Hermes' /init must be PID 1; the
    # listening healthcheck fails on the multi-process tree).
    expect(t[:disable_init_process]).to be(true)
    expect(t[:disable_zero_downtime_checks]).to be(true)
    # Dashboard basic-auth credentials MUST be generated before first boot —
    # without them the dashboard refuses to bind to 0.0.0.0 and the container
    # crash-loops. generate_secrets sets random values pre-build; the user
    # reads the password from the app's Environment Variables page.
    expect(t[:generate_secrets]).to include(
      "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD",
      "HERMES_DASHBOARD_BASIC_AUTH_SECRET"
    )
    expect(registry.featured.map { |f| f[:slug] }).to include("hermes-agent")
  end

  it "hides retired-engine templates but restores re-engined ones" do
    slugs = described_class.new.all.map { |t| t[:slug] }
    expect(slugs).to include("wordpress", "matomo", "bookstack") # re-engined to mariadb
    expect(slugs).not_to include("ghost")                        # still mysql → still pulled
  end
end
