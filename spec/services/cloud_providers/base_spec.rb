require "rails_helper"

RSpec.describe CloudProviders::Base do
  FAKE_API_BASE = "https://api.hetzner.cloud/v1".freeze

  # Concrete subclass to test Base through
  class ConcreteProvider < CloudProviders::Base
    def auth_header
      "Token test-key"
    end
  end

  let(:credential) { cloud_credentials(:one) }
  let(:provider) do
    p = ConcreteProvider.new(credential)
    # Force a known api_base regardless of PROVIDERS hash key style
    allow(p).to receive(:api_base).and_return(FAKE_API_BASE)
    p
  end

  describe "NotImplementedError on Base" do
    let(:base) { described_class.new(credential) }

    it "raises for regions" do
      expect { base.regions }.to raise_error(NotImplementedError)
    end

    it "raises for sizes" do
      expect { base.sizes }.to raise_error(NotImplementedError)
    end

    it "raises for create_server" do
      expect { base.create_server(name: "x", region: "x", size: "x") }.to raise_error(NotImplementedError)
    end

    it "raises for delete_server" do
      expect { base.delete_server("123") }.to raise_error(NotImplementedError)
    end

    it "raises for server_status" do
      expect { base.server_status("123") }.to raise_error(NotImplementedError)
    end

    it "raises for auth_header" do
      expect { base.send(:auth_header) }.to raise_error(NotImplementedError)
    end
  end

  describe "#api_get" do
    it "builds GET request and parses JSON response" do
      response_data = { "locations" => [ { "name" => "nbg1" } ] }
      stub_request(:get, "#{FAKE_API_BASE}/locations").to_return(
        status: 200, body: response_data.to_json
      )
      expect(provider.send(:api_get, "/locations")).to eq(response_data)
    end

    it "sets Authorization header" do
      stub_request(:get, "#{FAKE_API_BASE}/test")
        .with(headers: { "Authorization" => "Token test-key" })
        .to_return(status: 200, body: "{}")

      provider.send(:api_get, "/test")
      expect(WebMock).to have_requested(:get, "#{FAKE_API_BASE}/test")
        .with(headers: { "Authorization" => "Token test-key" })
    end
  end

  describe "#api_post" do
    it "sends POST with JSON body and parses response" do
      response_data = { "server" => { "id" => 1, "status" => "initializing" } }
      stub_request(:post, "#{FAKE_API_BASE}/servers")
        .with(
          body: { name: "test" }.to_json,
          headers: { "Content-Type" => "application/json", "Authorization" => "Token test-key" }
        )
        .to_return(status: 200, body: response_data.to_json)

      result = provider.send(:api_post, "/servers", { name: "test" })
      expect(result).to eq(response_data)
    end
  end

  describe "#api_delete" do
    it "sends DELETE request" do
      stub_request(:delete, "#{FAKE_API_BASE}/servers/123")
        .with(headers: { "Authorization" => "Token test-key" })
        .to_return(status: 204, body: "")

      provider.send(:api_delete, "/servers/123")
      expect(WebMock).to have_requested(:delete, "#{FAKE_API_BASE}/servers/123")
    end
  end
end
