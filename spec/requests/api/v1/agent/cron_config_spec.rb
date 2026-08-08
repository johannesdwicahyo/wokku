require "rails_helper"

RSpec.describe "agent cron config" do
  let(:server) { create(:server, wokkud_cron_enabled: true) }
  let(:headers) { { "Authorization" => "Bearer #{server.ingest_token}" } }

  it "returns the builder payload" do
    app = create(:app_record, server: server)
    task = create(:scheduled_task, app_record: app, enabled: true)
    get "/api/v1/agent/cron/config", headers: headers
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["version"]).to be_present
    expect(body["entries"].first["id"]).to eq(task.id)
  end

  it "rejects a bad token" do
    get "/api/v1/agent/cron/config", headers: { "Authorization" => "Bearer nope" }
    expect(response).to have_http_status(:unauthorized)
  end
end
