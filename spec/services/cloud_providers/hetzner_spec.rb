require "rails_helper"

RSpec.describe CloudProviders::Hetzner do
  HETZNER_API_BASE = "https://api.hetzner.cloud/v1".freeze

  let(:credential) { cloud_credentials(:one) }
  let(:provider) do
    p = described_class.new(credential)
    allow(p).to receive(:api_base).and_return(HETZNER_API_BASE)
    # Stub auth_header since fixture api_key uses encryption that may not decrypt in test env
    allow(p).to receive(:auth_header).and_return("Bearer test-hetzner-key")
    p
  end

  describe "#regions" do
    it "maps locations to expected format" do
      api_response = {
        "locations" => [
          { "name" => "nbg1", "description" => "Nuremberg DC Park 1", "city" => "Nuremberg", "country" => "DE" },
          { "name" => "fsn1", "description" => "Falkenstein DC Park 1", "city" => "Falkenstein", "country" => "DE" }
        ]
      }
      stub_request(:get, "#{HETZNER_API_BASE}/locations").to_return(status: 200, body: api_response.to_json)

      result = provider.regions
      expect(result.length).to eq(2)
      expect(result.first[:id]).to eq("nbg1")
      expect(result.first[:name]).to eq("Nuremberg DC Park 1")
      expect(result.first[:city]).to eq("Nuremberg")
      expect(result.first[:country]).to eq("DE")
    end

    it "returns empty array when no locations" do
      stub_request(:get, "#{HETZNER_API_BASE}/locations").to_return(status: 200, body: { "locations" => [] }.to_json)
      expect(provider.regions).to eq([])
    end
  end

  describe "#sizes" do
    it "returns static list of 4 Hetzner plans" do
      result = provider.sizes
      expect(result.length).to eq(4)
      ids = result.map { |s| s[:id] }
      expect(ids).to include("cx22")
      expect(ids).to include("cx52")
    end
  end

  describe "#create_server" do
    it "posts correct body and parses response" do
      api_response = {
        "server" => {
          "id" => 42,
          "status" => "initializing",
          "public_net" => { "ipv4" => { "ip" => "1.2.3.4" } }
        }
      }
      stub_request(:post, "#{HETZNER_API_BASE}/servers").to_return(status: 200, body: api_response.to_json)

      result = provider.create_server(name: "my-server", region: "nbg1", size: "cx22", ssh_key: "key-123")
      expect(result[:id]).to eq("42")
      expect(result[:ip]).to eq("1.2.3.4")
      expect(result[:status]).to eq("initializing")

      expect(WebMock).to have_requested(:post, "#{HETZNER_API_BASE}/servers").with { |req|
        body = JSON.parse(req.body)
        body["name"] == "my-server" &&
          body["server_type"] == "cx22" &&
          body["location"] == "nbg1" &&
          body["image"] == "ubuntu-24.04" &&
          body["ssh_keys"] == [ "key-123" ]
      }
    end

    it "without ssh_key omits ssh_keys from body" do
      api_response = {
        "server" => {
          "id" => 43, "status" => "initializing",
          "public_net" => { "ipv4" => { "ip" => "5.6.7.8" } }
        }
      }
      stub_request(:post, "#{HETZNER_API_BASE}/servers").to_return(status: 200, body: api_response.to_json)

      provider.create_server(name: "my-server", region: "nbg1", size: "cx22")
      expect(WebMock).to have_requested(:post, "#{HETZNER_API_BASE}/servers").with { |req|
        !JSON.parse(req.body).key?("ssh_keys")
      }
    end
  end

  describe "#delete_server" do
    it "sends DELETE to /servers/:id" do
      stub_request(:delete, "#{HETZNER_API_BASE}/servers/42").to_return(status: 204, body: "")
      provider.delete_server("42")
      expect(WebMock).to have_requested(:delete, "#{HETZNER_API_BASE}/servers/42")
    end
  end

  describe "#server_status" do
    it "returns server status string" do
      stub_request(:get, "#{HETZNER_API_BASE}/servers/42").to_return(
        status: 200, body: { "server" => { "status" => "running" } }.to_json
      )
      expect(provider.server_status("42")).to eq("running")
    end
  end

  describe "#auth_header" do
    it "uses Bearer token format" do
      cred = CloudCredential.new(provider: "hetzner", api_key: "my-known-key")
      allow(cred).to receive(:api_key).and_return("my-known-key")
      fresh = described_class.new(cred)
      expect(fresh.send(:auth_header)).to eq("Bearer my-known-key")
    end
  end

  describe "GET request" do
    it "includes Authorization header" do
      stub_request(:get, "#{HETZNER_API_BASE}/locations").to_return(
        status: 200, body: { "locations" => [] }.to_json
      )
      provider.regions
      expect(WebMock).to have_requested(:get, "#{HETZNER_API_BASE}/locations")
        .with(headers: { "Authorization" => /\ABearer / })
    end
  end
end
