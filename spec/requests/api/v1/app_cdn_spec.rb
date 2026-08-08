# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PATCH /api/v1/apps/:id/cdn", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }
  let(:toggle) { instance_double(Apps::Settings::CdnToggle, enable!: true, disable!: false) }

  before { allow(Apps::Settings::CdnToggle).to receive(:new).and_return(toggle) }

  it "enables CDN and returns the new state" do
    patch "/api/v1/apps/#{app_record.id}/cdn", params: { enabled: true }.to_json, headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("enabled" => true)
    expect(toggle).to have_received(:enable!)
  end

  it "disables CDN" do
    patch "/api/v1/apps/#{app_record.id}/cdn", params: { enabled: false }.to_json, headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("enabled" => false)
    expect(toggle).to have_received(:disable!)
  end

  it "returns 422 when enabled is missing" do
    patch "/api/v1/apps/#{app_record.id}/cdn", params: {}.to_json, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "returns 401 without a token" do
    patch "/api/v1/apps/#{app_record.id}/cdn", params: { enabled: true }.to_json, headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end
end
