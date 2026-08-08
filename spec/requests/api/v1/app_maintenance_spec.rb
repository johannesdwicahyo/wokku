# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PATCH /api/v1/apps/:id/maintenance", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }
  let(:toggle) { instance_double(Apps::Settings::MaintenanceToggle, enable!: true, disable!: false) }

  before { allow(Apps::Settings::MaintenanceToggle).to receive(:new).and_return(toggle) }

  it "enables maintenance" do
    patch "/api/v1/apps/#{app_record.id}/maintenance", params: { enabled: true }.to_json, headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("enabled" => true)
    expect(toggle).to have_received(:enable!)
  end

  it "disables maintenance" do
    patch "/api/v1/apps/#{app_record.id}/maintenance", params: { enabled: false }.to_json, headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("enabled" => false)
    expect(toggle).to have_received(:disable!)
  end

  it "returns 502 when Apps::Settings::Error (code: :dokku_error) is raised" do
    allow(toggle).to receive(:enable!).and_raise(Apps::Settings::Error.new("plugin missing", code: :dokku_error))
    patch "/api/v1/apps/#{app_record.id}/maintenance", params: { enabled: true }.to_json, headers: headers
    expect(response).to have_http_status(:bad_gateway)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("plugin missing")
    expect(body["error_code"]).to eq("dokku_command_failed")
  end
end
