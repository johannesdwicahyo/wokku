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

  it "create queues an immediate DNS check for a custom domain" do
    expect {
      post "/api/v1/apps/#{app_record.id}/domains", params: { hostname: "now.example.com" }, headers: headers
    }.to have_enqueued_job(DnsVerificationJob)
  end

  describe "ssl" do
    let(:domain) { app_record.domains.create!(hostname: "shop.example.com") }

    it "re-checks DNS and refuses honestly when the domain doesn't point here" do
      allow_any_instance_of(DnsVerificationJob).to receive(:dns_verified?).and_return(false)
      expect {
        post "/api/v1/apps/#{app_record.id}/domains/#{domain.id}/ssl", headers: headers
      }.not_to have_enqueued_job(EnableSslJob)
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("domain_not_verified")
      expect(response.body).to include("shop.example.com")
      expect(domain.reload.pending_action).to be_nil
    end

    it "verifies on the spot and queues issuance once DNS points here" do
      allow_any_instance_of(DnsVerificationJob).to receive(:dns_verified?).and_return(true)
      expect {
        post "/api/v1/apps/#{app_record.id}/domains/#{domain.id}/ssl", headers: headers
      }.to have_enqueued_job(EnableSslJob)
      expect(response).to have_http_status(:accepted)
      expect(domain.reload.dns_verified).to be true
    end
  end
end
