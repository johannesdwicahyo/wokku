require "rails_helper"

RSpec.describe "agent storage backup runs" do
  let(:server) { create(:server) }
  let(:headers) { { "Authorization" => "Bearer #{server.ingest_token}" } }
  let(:path) { "/api/v1/agent/storage_backup_runs" }

  it "records a run" do
    post path, params: { kind: "sync", status: "ok", objects: 3, bytes: 10, error: "note" }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(server.storage_backup_runs.sole).to have_attributes(kind: "sync", objects: 3, bytes: 10, error: "note")
  end

  it "rejects a bad token" do
    post path, params: { kind: "sync", status: "ok" }, headers: { "Authorization" => "Bearer nope" }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects an unknown kind" do
    post path, params: { kind: "x", status: "ok" }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end
end
