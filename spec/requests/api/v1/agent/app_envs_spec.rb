require "rails_helper"

RSpec.describe "agent app env" do
  let(:server) { create(:server) }
  let(:headers) { { "Authorization" => "Bearer #{server.ingest_token}" } }

  it "returns the app's config from EnvVar rows — cp env truth (B6 W3)" do
    app = create(:app_record, server: server, name: "myapp")
    app.env_vars.create!(key: "DATABASE_URL", value: "postgres://x")
    expect(Hosts::Ssh).not_to receive(:new)
    get "/api/v1/agent/apps/myapp/env", headers: headers
    expect(response.parsed_body).to eq("env" => { "DATABASE_URL" => "postgres://x" })
  end

  it "404s typed for an app on another server" do
    create(:app_record, server: create(:server), name: "elsewhere")
    get "/api/v1/agent/apps/elsewhere/env", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body["error_code"]).to eq("app_not_on_server")
  end

  it "404s an app name that doesn't exist anywhere" do
    get "/api/v1/agent/apps/nope/env", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body["error_code"]).to eq("app_not_on_server")
  end

  it "rejects a bad token" do
    create(:app_record, server: server, name: "myapp")
    get "/api/v1/agent/apps/myapp/env", headers: { "Authorization" => "Bearer nope" }
    expect(response).to have_http_status(:unauthorized)
  end
end
