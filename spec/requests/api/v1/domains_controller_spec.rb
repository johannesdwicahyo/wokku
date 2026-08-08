# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::DomainsController (deep)", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  # W6: domain writes are control-plane-only — no Dokku stubs needed, and a
  # dokku outage can no longer fail these endpoints.

  it "index lists app's domains" do
    app_record.domains.create!(hostname: "app.example.com")
    get "/api/v1/apps/#{app_record.id}/domains", headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body).any? { |d| d["hostname"] == "app.example.com" }).to be_truthy
  end

  it "create adds a domain" do
    expect {
      post "/api/v1/apps/#{app_record.id}/domains",
        params: { hostname: "new.example.com" },
        headers: headers
    }.to change { app_record.domains.count }.by(1)
    expect(response).to have_http_status(:created)
  end

  it "create rejects invalid hostname" do
    post "/api/v1/apps/#{app_record.id}/domains",
      params: { hostname: "" },
      headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "create never touches dokku" do
    expect(Hosts::Ssh).not_to receive(:new)
    post "/api/v1/apps/#{app_record.id}/domains",
      params: { hostname: "new.example.com" },
      headers: headers
    expect(response).to have_http_status(:created)
  end

  it "destroy removes a domain" do
    d = app_record.domains.create!(hostname: "del.example.com")
    expect {
      delete "/api/v1/apps/#{app_record.id}/domains/#{d.id}", headers: headers
    }.to change { app_record.domains.count }.by(-1)
    expect(response).to have_http_status(:success)
  end
end
