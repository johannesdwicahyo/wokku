require "rails_helper"

RSpec.describe "API::V1::Requests::Ingest", type: :request do
  let(:server)     { servers(:one) }
  let(:app_record) { app_records(:one) }
  # NOTE: do NOT name this `let(:app)` — Rack::Test uses `#app` for its
  # Rack-app accessor and shadowing it produces the world's most confusing
  # NoMethodError. Same trap documented in spec/requests/api/v1/logs/ingest_spec.rb.
  let(:token)   { server.ingest_token }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/x-ndjson" } }

  describe "POST /api/v1/requests/ingest" do
    let(:base_entry) do
      {
        ts: "2026-05-27T12:00:00Z",
        container: "#{app_record.name}.web.1",
        method: "GET",
        path: "/api/users",
        status: 200,
        response_time_ms: 42,
        bytes_sent: 1234,
        remote_addr: "1.2.3.4"
      }
    end

    it "ingests one row per NDJSON entry" do
      body = [ base_entry, base_entry.merge(path: "/api/other") ].map(&:to_json).join("\n")
      expect {
        post "/api/v1/requests/ingest", params: body, headers: headers
      }.to change { RequestSample.count }.by(2)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["ingested"]).to eq(2)
    end

    it "resolves app_record_id from a container of the form <app>.web.<n>" do
      post "/api/v1/requests/ingest", params: base_entry.to_json, headers: headers
      expect(RequestSample.last.app_record_id).to eq(app_record.id)
    end

    it "resolves app_record_id by Domain hostname match (custom domain path)" do
      app_record.domains.create!(hostname: "custom.example.com")
      entry = base_entry.merge(container: "custom.example.com")
      post "/api/v1/requests/ingest", params: entry.to_json, headers: headers
      expect(RequestSample.last.app_record_id).to eq(app_record.id)
    end

    it "still ingests unmatched vhosts with nil app_record_id" do
      entry = base_entry.merge(container: "unknown-host.example.com")
      expect {
        post "/api/v1/requests/ingest", params: entry.to_json, headers: headers
      }.to change { RequestSample.count }.by(1)
      expect(RequestSample.last.app_record_id).to be_nil
    end

    it "returns 401 with no token" do
      post "/api/v1/requests/ingest", params: "", headers: { "Content-Type" => "application/x-ndjson" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 413 above MAX_LINES_PER_REQUEST" do
      huge = (1..1_001).map { base_entry.to_json }.join("\n")
      post "/api/v1/requests/ingest", params: huge, headers: headers
      expect(response).to have_http_status(:payload_too_large)
    end

    it "returns 400 on malformed NDJSON" do
      post "/api/v1/requests/ingest", params: "not-json", headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it "trims path to MAX_PATH_BYTES" do
      entry = base_entry.merge(path: "/" + ("x" * 3000))
      post "/api/v1/requests/ingest", params: entry.to_json, headers: headers
      expect(RequestSample.last.path.length).to be <= 2048
    end
  end
end
