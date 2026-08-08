require "rails_helper"

RSpec.describe CloudProviders::Vultr do
  VULTR_API_BASE = "https://api.vultr.com/v2".freeze

  let(:credential) { CloudCredential.new(provider: "vultr", api_key: "vultr-test-key-abc") }
  let(:provider) do
    p = described_class.new(credential)
    allow(p).to receive(:api_base).and_return(VULTR_API_BASE)
    p
  end

  describe "#regions" do
    it "filters to locations with in_dc_2 option" do
      api_response = {
        "regions" => [
          { "id" => "ewr", "city" => "New Jersey", "country" => "US", "options" => [ "in_dc_2", "ddos_protection" ] },
          { "id" => "sea", "city" => "Seattle", "country" => "US", "options" => [ "in_dc_2" ] },
          { "id" => "atl", "city" => "Atlanta", "country" => "US", "options" => [] }
        ]
      }
      stub_request(:get, "#{VULTR_API_BASE}/regions").to_return(status: 200, body: api_response.to_json)

      result = provider.regions
      expect(result.length).to eq(2)
      ids = result.map { |r| r[:id] }
      expect(ids).to include("ewr", "sea")
      expect(ids).not_to include("atl")
    end

    it "maps to expected format" do
      api_response = {
        "regions" => [
          { "id" => "sgp", "city" => "Singapore", "country" => "SG", "options" => [ "in_dc_2" ] }
        ]
      }
      stub_request(:get, "#{VULTR_API_BASE}/regions").to_return(status: 200, body: api_response.to_json)

      result = provider.regions
      expect(result.length).to eq(1)
      expect(result.first[:id]).to eq("sgp")
      expect(result.first[:name]).to eq("Singapore, SG")
      expect(result.first[:city]).to eq("Singapore")
      expect(result.first[:country]).to eq("SG")
    end

    it "returns empty array when no regions" do
      stub_request(:get, "#{VULTR_API_BASE}/regions").to_return(status: 200, body: { "regions" => [] }.to_json)
      expect(provider.regions).to eq([])
    end
  end

  describe "#sizes" do
    it "returns static list of 4 Vultr plans" do
      result = provider.sizes
      expect(result.length).to eq(4)
      ids = result.map { |s| s[:id] }
      expect(ids).to include("vc2-1c-1gb", "vc2-4c-8gb")
    end
  end

  describe "#create_server" do
    it "posts correct body and parses response" do
      api_response = {
        "instance" => { "id" => "uuid-abc-123", "main_ip" => "99.88.77.66", "status" => "pending" }
      }
      stub_request(:post, "#{VULTR_API_BASE}/instances").to_return(status: 200, body: api_response.to_json)

      result = provider.create_server(name: "my-vps", region: "sgp", size: "vc2-1c-2gb", ssh_key: "key-456")
      expect(result[:id]).to eq("uuid-abc-123")
      expect(result[:ip]).to eq("99.88.77.66")
      expect(result[:status]).to eq("pending")

      expect(WebMock).to have_requested(:post, "#{VULTR_API_BASE}/instances").with { |req|
        body = JSON.parse(req.body)
        body["label"] == "my-vps" &&
          body["region"] == "sgp" &&
          body["plan"] == "vc2-1c-2gb" &&
          body["os_id"] == 2284 &&
          body["hostname"] == "my-vps" &&
          body["sshkey_id"] == [ "key-456" ]
      }
    end

    it "without ssh_key omits sshkey_id from body" do
      api_response = {
        "instance" => { "id" => "uuid-xyz", "main_ip" => "1.1.1.1", "status" => "pending" }
      }
      stub_request(:post, "#{VULTR_API_BASE}/instances").to_return(status: 200, body: api_response.to_json)

      provider.create_server(name: "my-vps", region: "sgp", size: "vc2-1c-2gb")
      expect(WebMock).to have_requested(:post, "#{VULTR_API_BASE}/instances").with { |req|
        !JSON.parse(req.body).key?("sshkey_id")
      }
    end
  end

  describe "#delete_server" do
    it "sends DELETE to /instances/:id" do
      stub_request(:delete, "#{VULTR_API_BASE}/instances/uuid-abc-123").to_return(status: 204, body: "")
      provider.delete_server("uuid-abc-123")
      expect(WebMock).to have_requested(:delete, "#{VULTR_API_BASE}/instances/uuid-abc-123")
    end
  end

  describe "#server_status" do
    it "returns instance status string" do
      stub_request(:get, "#{VULTR_API_BASE}/instances/uuid-abc-123").to_return(
        status: 200, body: { "instance" => { "status" => "active" } }.to_json
      )
      expect(provider.server_status("uuid-abc-123")).to eq("active")
    end
  end

  describe "#auth_header" do
    it "uses Bearer token format" do
      expect(provider.send(:auth_header)).to eq("Bearer vultr-test-key-abc")
    end
  end

  describe "GET request" do
    it "includes Authorization header" do
      stub_request(:get, "#{VULTR_API_BASE}/regions").to_return(
        status: 200, body: { "regions" => [] }.to_json
      )
      provider.regions
      expect(WebMock).to have_requested(:get, "#{VULTR_API_BASE}/regions")
        .with(headers: { "Authorization" => /\ABearer / })
    end
  end
end
