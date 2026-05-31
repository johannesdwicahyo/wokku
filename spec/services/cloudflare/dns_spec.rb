require "rails_helper"

RSpec.describe Cloudflare::Dns do
  BASE_URL = "https://api.cloudflare.com/client/v4".freeze
  ZONE_ID = "zone_test".freeze

  around do |ex|
    orig_token = ENV["CLOUDFLARE_API_TOKEN"]
    orig_zone  = ENV["CLOUDFLARE_ZONE_ID"]
    ENV["CLOUDFLARE_API_TOKEN"] = "tok_test"
    ENV["CLOUDFLARE_ZONE_ID"] = ZONE_ID
    ex.run
  ensure
    ENV["CLOUDFLARE_API_TOKEN"] = orig_token
    ENV["CLOUDFLARE_ZONE_ID"] = orig_zone
  end

  def stub_find_record(name:, result:)
    stub_request(:get, "#{BASE_URL}/zones/#{ZONE_ID}/dns_records")
      .with(query: hash_including(type: "A", name: name))
      .to_return(status: 200, body: { success: true, result: result }.to_json)
  end

  describe "#create_app_record" do
    it "creates a new A record when missing" do
      stub_find_record(name: "my-app.wokku.cloud", result: [])
      stub_request(:post, "#{BASE_URL}/zones/#{ZONE_ID}/dns_records")
        .to_return(status: 200, body: { success: true, result: { id: "rec1" } }.to_json)

      hostname = described_class.new.create_app_record("my-app", "1.2.3.4")
      expect(hostname).to eq("my-app.wokku.cloud")
    end

    it "updates when IP differs" do
      stub_find_record(name: "my-app.wokku.cloud", result: [ { "id" => "rec1", "content" => "9.9.9.9" } ])
      stub_request(:put, "#{BASE_URL}/zones/#{ZONE_ID}/dns_records/rec1")
        .to_return(status: 200, body: { success: true, result: { id: "rec1" } }.to_json)

      expect { described_class.new.create_app_record("my-app", "1.2.3.4") }.not_to raise_error
    end

    it "skips when IP already matches" do
      stub_find_record(name: "my-app.wokku.cloud", result: [ { "id" => "rec1", "content" => "1.2.3.4" } ])
      expect { described_class.new.create_app_record("my-app", "1.2.3.4") }.not_to raise_error
    end
  end

  describe "#delete_app_record" do
    it "issues delete when record exists" do
      stub_find_record(name: "doomed.wokku.cloud", result: [ { "id" => "rec1" } ])
      stub_request(:delete, "#{BASE_URL}/zones/#{ZONE_ID}/dns_records/rec1")
        .to_return(status: 200, body: { success: true, result: {} }.to_json)

      expect { described_class.new.delete_app_record("doomed") }.not_to raise_error
    end

    it "is a no-op when record missing" do
      stub_find_record(name: "ghost.wokku.cloud", result: [])
      expect { described_class.new.delete_app_record("ghost") }.not_to raise_error
    end
  end

  describe "#verify!" do
    it "returns zone metadata" do
      stub_request(:get, "#{BASE_URL}/zones/#{ZONE_ID}")
        .to_return(status: 200, body: {
          success: true,
          result: { "name" => "wokku.cloud", "status" => "active", "name_servers" => %w[a.ns b.ns] }
        }.to_json)

      info = described_class.new.verify!
      expect(info[:name]).to eq("wokku.cloud")
      expect(info[:status]).to eq("active")
    end
  end

  describe "#list_app_records" do
    it "filters to wokku.cloud subdomains only" do
      stub_request(:get, "#{BASE_URL}/zones/#{ZONE_ID}/dns_records")
        .with(query: hash_including(type: "A"))
        .to_return(status: 200, body: {
          success: true,
          result: [
            { "name" => "my-app.wokku.cloud" },
            { "name" => "other.example.com" },
            { "name" => "wokku.cloud" }
          ]
        }.to_json)

      records = described_class.new.list_app_records
      expect(records.map { |r| r["name"] }).to eq([ "my-app.wokku.cloud" ])
    end
  end

  describe "API errors" do
    it "raises ApiError with messages" do
      stub_request(:get, "#{BASE_URL}/zones/#{ZONE_ID}")
        .to_return(status: 200, body: {
          success: false, errors: [ { "message" => "Invalid token" } ]
        }.to_json)

      expect { described_class.new.verify! }.to raise_error(Cloudflare::Dns::ApiError, /Invalid token/)
    end
  end

  # Dual-zone cutover helpers (2026-05-29). Controls which Cloudflare
  # zones receive writes during the *.wokku.cloud → *.wokku.app rollout.
  describe ".wokku_app_enabled? + .canonical_domain + .enabled_domains" do
    around do |ex|
      orig = ENV["WOKKU_APP_ENABLED"]
      ex.run
    ensure
      ENV["WOKKU_APP_ENABLED"] = orig
    end

    it "is off by default" do
      ENV["WOKKU_APP_ENABLED"] = nil
      expect(described_class.wokku_app_enabled?).to eq(false)
      expect(described_class.canonical_domain).to eq("wokku.cloud")
      expect(described_class.enabled_domains).to eq([ "wokku.cloud" ])
    end

    it "flips on when WOKKU_APP_ENABLED=true" do
      ENV["WOKKU_APP_ENABLED"] = "true"
      expect(described_class.wokku_app_enabled?).to eq(true)
      expect(described_class.canonical_domain).to eq("wokku.app")
      expect(described_class.enabled_domains).to eq(%w[wokku.cloud wokku.app])
    end

    it "always lists both as owned_domains so URL matchers recognise either" do
      expect(described_class.owned_domains).to contain_exactly("wokku.cloud", "wokku.app")
    end
  end

  describe ".for_each_enabled" do
    around do |ex|
      orig_app_zone = ENV["CLOUDFLARE_ZONE_ID_WOKKU_APP"]
      orig_flag     = ENV["WOKKU_APP_ENABLED"]
      ENV["CLOUDFLARE_ZONE_ID_WOKKU_APP"] = "zone_app_test"
      ex.run
    ensure
      ENV["CLOUDFLARE_ZONE_ID_WOKKU_APP"] = orig_app_zone
      ENV["WOKKU_APP_ENABLED"] = orig_flag
    end

    it "yields once with the legacy zone when flag is off" do
      ENV["WOKKU_APP_ENABLED"] = nil
      domains = []
      described_class.for_each_enabled { |dns| domains << dns.domain }
      expect(domains).to eq([ "wokku.cloud" ])
    end

    it "yields both zones when flag is on" do
      ENV["WOKKU_APP_ENABLED"] = "true"
      domains = []
      described_class.for_each_enabled { |dns| domains << dns.domain }
      expect(domains).to eq(%w[wokku.cloud wokku.app])
    end
  end

  describe "#initialize with domain:" do
    around do |ex|
      orig_app_zone = ENV["CLOUDFLARE_ZONE_ID_WOKKU_APP"]
      ENV["CLOUDFLARE_ZONE_ID_WOKKU_APP"] = "zone_app_test"
      ex.run
    ensure
      ENV["CLOUDFLARE_ZONE_ID_WOKKU_APP"] = orig_app_zone
    end

    it "writes records into the wokku.app zone when constructed with domain: \"wokku.app\"" do
      stub_request(:get, "#{BASE_URL}/zones/zone_app_test/dns_records")
        .with(query: hash_including(type: "A", name: "x.wokku.app"))
        .to_return(status: 200, body: { success: true, result: [] }.to_json)
      stub_request(:post, "#{BASE_URL}/zones/zone_app_test/dns_records")
        .to_return(status: 200, body: { success: true, result: { id: "rec1" } }.to_json)

      hostname = described_class.new(domain: "wokku.app").create_app_record("x", "5.6.7.8")
      expect(hostname).to eq("x.wokku.app")
    end

    it "raises when called with an unmapped domain" do
      expect { described_class.new(domain: "example.com") }.to raise_error(ArgumentError, /no zone mapping/)
    end
  end
end
