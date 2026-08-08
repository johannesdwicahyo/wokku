# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::ConfigController (deep)", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "show succeeds without touching the host — env truth is the control plane (B6 W3)" do
    expect(Hosts::Ssh).not_to receive(:new)
    get "/api/v1/apps/#{app_record.id}/config", headers: headers
    expect(response).to have_http_status(:ok)
  end

  it "update rejects non-hash vars" do
    put "/api/v1/apps/#{app_record.id}/config", params: { vars: "invalid" }, headers: headers
    expect(response).to have_http_status(:bad_request)
  end

  it "destroy succeeds without touching the host — the dokku mirror died with cp env truth (B6)" do
    app_record.env_vars.create!(key: "DEL_ME", value: "x")
    expect(Hosts::Ssh).not_to receive(:new)
    delete "/api/v1/apps/#{app_record.id}/config",
      params: { keys: [ "DEL_ME" ] },
      headers: headers
    expect(response).to have_http_status(:ok)
    expect(app_record.env_vars.where(key: "DEL_ME")).to be_empty
  end
end
