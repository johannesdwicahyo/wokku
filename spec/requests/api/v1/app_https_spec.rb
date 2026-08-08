# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PATCH /api/v1/apps/:id/https", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }
  let(:toggle) { instance_double(Apps::Settings::HttpsToggle, enable!: true, disable!: false) }

  before { allow(Apps::Settings::HttpsToggle).to receive(:new).and_return(toggle) }

  it "enables HTTPS and returns the new state" do
    patch "/api/v1/apps/#{app_record.id}/https", params: { enabled: true }.to_json, headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("enabled" => true)
    expect(toggle).to have_received(:enable!)
  end

  it "disables HTTPS" do
    patch "/api/v1/apps/#{app_record.id}/https", params: { enabled: false }.to_json, headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("enabled" => false)
    expect(toggle).to have_received(:disable!)
  end

  it "returns 422 when enabled is missing" do
    patch "/api/v1/apps/#{app_record.id}/https", params: {}.to_json, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "returns 502 when Apps::Settings::Error (code: :dokku_error) is raised" do
    allow(toggle).to receive(:enable!).and_raise(Apps::Settings::Error.new("dokku err", code: :dokku_error))
    patch "/api/v1/apps/#{app_record.id}/https", params: { enabled: true }.to_json, headers: headers
    expect(response).to have_http_status(:bad_gateway)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("dokku err")
    expect(body["error_code"]).to eq("dokku_command_failed")
  end

  it "returns 401 without a token" do
    patch "/api/v1/apps/#{app_record.id}/https", params: { enabled: true }.to_json, headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 404 for an unknown app" do
    patch "/api/v1/apps/no-such-app/https", params: { enabled: true }.to_json, headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
