# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::StorageController", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  shared_examples "retired storage endpoint" do
    it "returns the typed 410 payload" do
      expect(response).to have_http_status(:gone)
      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("storage_retired")
      expect(body["error"]).to eq("Volume mount management has been retired")
      expect(body["hint"]).to include("platform-managed")
      expect(body["retryable"]).to be false
    end
  end

  describe "GET /storage" do
    before { get api_v1_app_storage_path(app_record), headers: headers }
    include_examples "retired storage endpoint"
  end

  describe "POST /storage" do
    before { post api_v1_app_storage_path(app_record), params: { mount: "/host/data:/app/data" }, headers: headers }
    include_examples "retired storage endpoint"
  end

  describe "DELETE /storage" do
    before { delete api_v1_app_storage_path(app_record), params: { mount: "/host/data:/app/data" }, headers: headers }
    include_examples "retired storage endpoint"
  end

  it "returns 401 without token" do
    get api_v1_app_storage_path(app_record)
    expect(response).to have_http_status(:unauthorized)
  end
end
