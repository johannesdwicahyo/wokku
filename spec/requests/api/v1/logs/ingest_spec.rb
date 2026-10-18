require "rails_helper"

RSpec.describe "API::V1::Logs::Ingest", type: :request do
  let(:server)     { servers(:one) }
  let(:app_record) { app_records(:one) }
  # NOTE: don't name this `let(:app)` — `app` is the Rack-app accessor
  # used by Rack::Test internally. Shadowing it makes Rack::Test try to
  # call `.call(env)` on an AppRecord, which fails with the world's
  # most confusing NoMethodError.
  let(:token)  { server.ingest_token }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/x-ndjson" } }

  describe "POST /api/v1/logs/ingest" do
    let(:ndjson) do
      [
        { ts: "2026-05-25T12:00:00Z", container: "#{app_record.name}.web.1", message: "GET / 200" },
        { ts: "2026-05-25T12:00:01Z", container: "#{app_record.name}.web.1", message: "ERROR connection refused" }
      ].map(&:to_json).join("\n")
    end

    it "ingests the batch and returns count" do
      expect {
        post "/api/v1/logs/ingest", params: ndjson, headers: headers
      }.to change { Log.count }.by(2)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["ingested"]).to eq(2)
    end

    it "strips NUL bytes instead of failing the whole batch (Postgres text can't hold them)" do
      body = [
        { ts: "2026-05-25T12:00:00Z", container: "#{app_record.name}.web.1", message: "bin\u0000ary out" },
        { ts: "2026-05-25T12:00:01Z", container: "#{app_record.name}.web.1", message: "fine" }
      ].map(&:to_json).join("\n")
      expect {
        post "/api/v1/logs/ingest", params: body, headers: headers
      }.to change { Log.count }.by(2)
      expect(response).to have_http_status(:ok)
      expect(Log.where(container: "#{app_record.name}.web.1").pluck(:line)).to include("binary out")
    end

    it "maps container name to the app record" do
      post "/api/v1/logs/ingest", params: ndjson, headers: headers
      log = Log.where(container: "#{app_record.name}.web.1").order(:ts).first
      expect(log.app_record_id).to eq(app_record.id)
    end

    it "auto-detects the level from line content" do
      post "/api/v1/logs/ingest", params: ndjson, headers: headers
      logs = Log.where(server: server).order(:ts)
      expect(logs[0].level).to eq("info")
      expect(logs[1].level).to eq("error")
    end

    it "still ingests system containers with nil app_record_id" do
      body = { ts: "2026-05-25T12:00:00Z", container: "dokku-postgres.svc", message: "checkpoint" }.to_json
      expect {
        post "/api/v1/logs/ingest", params: body, headers: headers
      }.to change { Log.count }.by(1)
      log = Log.where(container: "dokku-postgres.svc").last
      expect(log.app_record_id).to be_nil
    end

    it "trims lines longer than MAX_LINE_BYTES" do
      huge = "x" * 20_000
      body = { ts: "2026-05-25T12:00:00Z", container: "#{app_record.name}.web.1", message: huge }.to_json
      post "/api/v1/logs/ingest", params: body, headers: headers
      log = Log.last
      expect(log.line.length).to be <= 16_384
    end

    it "returns 400 on malformed NDJSON" do
      post "/api/v1/logs/ingest", params: "not-json", headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 413 if batch exceeds MAX_LINES_PER_REQUEST" do
      huge_batch = (1..1_001).map { |i| { ts: "2026-05-25T12:00:00Z", container: "x.web.1", message: "line-#{i}" }.to_json }.join("\n")
      post "/api/v1/logs/ingest", params: huge_batch, headers: headers
      expect(response).to have_http_status(:payload_too_large)
    end

    it "skips entries with blank container" do
      body = { ts: "2026-05-25T12:00:00Z", container: "", message: "x" }.to_json
      expect {
        post "/api/v1/logs/ingest", params: body, headers: headers
      }.not_to change { Log.count }
    end

    it "skips entries with blank message" do
      body = { ts: "2026-05-25T12:00:00Z", container: "x.web.1", message: "" }.to_json
      expect {
        post "/api/v1/logs/ingest", params: body, headers: headers
      }.not_to change { Log.count }
    end
  end

  describe "authentication" do
    it "rejects requests with no token" do
      post "/api/v1/logs/ingest", params: "", headers: { "Content-Type" => "application/x-ndjson" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects requests with an invalid token" do
      post "/api/v1/logs/ingest", params: "", headers: { "Authorization" => "Bearer not-a-token" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts requests with a valid server token" do
      body = { ts: Time.current.iso8601, container: "x.web.1", message: "hi" }.to_json
      post "/api/v1/logs/ingest", params: body, headers: headers
      expect(response).to have_http_status(:ok)
    end
  end
end
