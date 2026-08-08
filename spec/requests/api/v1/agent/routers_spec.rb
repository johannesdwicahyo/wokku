require "rails_helper"

RSpec.describe "Api::V1::Agent::Routers" do
  before do
    allow(Wokku.config).to receive(:owned_domains).and_return([ "wokku.app", "wokku.cloud" ])
  end

  let(:server)  { create(:server) }
  let(:headers) { { "Authorization" => "Bearer #{server.ingest_token}" } }

  describe "GET /api/v1/agent/router/config" do
    it "returns the routing config with its version" do
      server.update!(wokkud_router_enabled: false) # model default is now true
      app = create(:app_record, server: server, name: "alpha")
      create(:domain, app_record: app, hostname: "alpha.wokku.app")

      get "/api/v1/agent/router/config", headers: headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["version"]).to eq(Routers::ConfigBuilder.new(server).version)
      expect(body["apps"].first).to include("name" => "alpha", "container_port" => 5000)
      expect(body["listen_mode"]).to eq("shadow")
    end

    it "rejects a bad token" do
      get "/api/v1/agent/router/config", headers: { "Authorization" => "Bearer wrong" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a query-param token with no Authorization header (query-param auth is tls_allowed-only)" do
      get "/api/v1/agent/router/config", params: { token: server.ingest_token }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/agent/router/tls_allowed" do
    # ponytail: named app_record, not app — `app` is Rack::Test's own
    # method (the dispatch target for get/post); a `let(:app)` here shadows
    # it and breaks every request in this group (confirmed).
    let(:app_record) { create(:app_record, server: server) }

    it "allows a dns-verified domain on this server, via query-param token" do
      create(:domain, app_record: app_record, hostname: "www.example.com", dns_verified: true)
      get "/api/v1/agent/router/tls_allowed",
          params: { domain: "WWW.example.com", token: server.ingest_token }
      expect(response).to have_http_status(:ok)
    end

    it "refuses unverified domains with the typed payload" do
      create(:domain, app_record: app_record, hostname: "www.example.com", dns_verified: false)
      get "/api/v1/agent/router/tls_allowed",
          params: { domain: "www.example.com", token: server.ingest_token }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error_code"]).to eq("domain_not_verified")
    end

    it "refuses domains that live on a different server" do
      other = create(:app_record, server: create(:server))
      create(:domain, app_record: other, hostname: "www.example.com", dns_verified: true)
      get "/api/v1/agent/router/tls_allowed",
          params: { domain: "www.example.com", token: server.ingest_token }
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects a missing token" do
      get "/api/v1/agent/router/tls_allowed", params: { domain: "x.example.com" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
