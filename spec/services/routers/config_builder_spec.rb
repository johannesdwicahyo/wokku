require "rails_helper"

RSpec.describe Routers::ConfigBuilder do
  before do
    allow(Wokku.config).to receive(:owned_domains).and_return([ "wokku.app", "wokku.cloud" ])
  end

  let(:server) { create(:server) }
  let(:builder) { described_class.new(server) }

  it "emits apps sorted by name with sorted domains, tls modes, and upstreams" do
    app_b = create(:app_record, server: server, name: "bravo", container_port: 3000)
    app_a = create(:app_record, server: server, name: "alpha")
    create(:domain, app_record: app_a, hostname: "alpha.wokku.app")
    create(:domain, app_record: app_b, hostname: "www.example.com", dns_verified: true)
    create(:domain, app_record: app_b, hostname: "bravo.wokku.app")
    create(:domain, app_record: app_b, hostname: "unverified.example.com", dns_verified: false)

    apps = builder.as_json.fetch("apps")
    expect(apps.map { |a| a["name"] }).to eq(%w[alpha bravo])
    bravo = apps.last
    expect(bravo["container_port"]).to eq(3000)
    expect(bravo["domains"]).to eq([
      { "hostname" => "bravo.wokku.app", "tls" => "wildcard" },
      { "hostname" => "unverified.example.com", "tls" => "none" },
      { "hostname" => "www.example.com", "tls" => "on_demand" }
    ])
    expect(bravo["upstreams"]).to eq([ { "local" => true } ])
  end

  it "skips apps without domains and carries the wildcard cert + listen_mode" do
    server.update!(wokkud_router_enabled: false) # model default is now true
    create(:app_record, server: server, name: "nodomains")
    cert = create(:wildcard_certificate)

    json = builder.as_json
    expect(json["apps"]).to eq([])
    expect(json["listen_mode"]).to eq("shadow")
    expect(json["wildcard_cert"]).to include("fullchain_pem" => cert.fullchain_pem, "key_pem" => cert.key_pem)

    server.update!(wokkud_router_enabled: true)
    expect(described_class.new(server).as_json["listen_mode"]).to eq("live")
  end

  it "computes a stable sha256 version that changes when routing changes" do
    app = create(:app_record, server: server, name: "alpha")
    create(:domain, app_record: app, hostname: "alpha.wokku.app")

    v1 = builder.version
    expect(v1).to eq(described_class.new(server).version)
    expect(v1).to match(/\A[0-9a-f]{64}\z/)

    create(:domain, app_record: app, hostname: "alpha2.wokku.app")
    expect(described_class.new(server).version).not_to eq(v1)
  end

  it "renders a dial upstream at the swarm port for wokkud-lifecycle apps, and changes version on flip" do
    app = create(:app_record, server: server, name: "alpha", wokkud_lifecycle: false, swarm_port: 31005)
    create(:domain, app_record: app, hostname: "alpha.wokku.app")

    v_before = builder.version
    apps = builder.as_json.fetch("apps")
    expect(apps.first["upstreams"]).to eq([ { "local" => true } ])

    app.update!(wokkud_lifecycle: true)

    apps_after = described_class.new(server).as_json.fetch("apps")
    expect(apps_after.first["upstreams"]).to eq([ { "dial" => "127.0.0.1:31005" } ])
    expect(described_class.new(server).version).not_to eq(v_before)
  end

  it "emits maintenance only when set, changing the version, and omits the key otherwise" do
    app = create(:app_record, server: server, name: "alpha")
    create(:domain, app_record: app, hostname: "alpha.wokku.app")

    v_before = builder.version
    expect(builder.as_json.fetch("apps").first).not_to have_key("maintenance")

    app.update!(maintenance_mode: true)

    entry = described_class.new(server).as_json.fetch("apps").first
    expect(entry["maintenance"]).to be true
    # Key ordering stays stable: maintenance is appended after the fixed keys.
    expect(entry.keys).to eq(%w[name container_port domains upstreams maintenance])
    expect(described_class.new(server).version).not_to eq(v_before)
  end

  it "falls back to the local upstream when a wokkud-lifecycle app has no swarm_port yet" do
    app = create(:app_record, server: server, name: "alpha", wokkud_lifecycle: true, swarm_port: nil)
    create(:domain, app_record: app, hostname: "alpha.wokku.app")

    apps = builder.as_json.fetch("apps")
    expect(apps.first["upstreams"]).to eq([ { "local" => true } ])
  end

  describe "static routes (WOKKU_STATIC_ROUTES)" do
    let(:env) { "#{server.name} s3.wokku.cloud 127.0.0.1:9100, other-host files.wokku.cloud 127.0.0.1:9200" }

    it "routes a fixed hostname to a local port on the named server only" do
      stub_const("ENV", ENV.to_h.merge("WOKKU_STATIC_ROUTES" => env))
      apps = builder.as_json.fetch("apps")
      expect(apps).to eq([ {
        "name" => "static-s3.wokku.cloud",
        "container_port" => 0,
        "domains" => [ { "hostname" => "s3.wokku.cloud", "tls" => "wildcard" } ],
        "upstreams" => [ { "dial" => "127.0.0.1:9100" } ]
      } ])
    end

    it "leaves the config (and its version) untouched when unset" do
      v = builder.version
      stub_const("ENV", ENV.to_h.except("WOKKU_STATIC_ROUTES"))
      expect(described_class.new(server).as_json.fetch("apps")).to eq([])
      expect(described_class.new(server).version).to eq(v)
    end
  end
end
