# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::BuildpacksController", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  shared_examples "retired buildpacks endpoint" do
    it "returns the typed 410 payload" do
      expect(response).to have_http_status(:gone)
      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("buildpacks_retired")
      expect(body["error"]).to eq("Buildpack configuration has been retired")
      expect(body["hint"]).to include("image-based")
      expect(body["retryable"]).to be false
    end
  end

  describe "GET /buildpacks" do
    before { get api_v1_app_buildpacks_path(app_record), headers: headers }
    include_examples "retired buildpacks endpoint"
  end

  describe "POST /buildpacks" do
    before { post api_v1_app_buildpacks_path(app_record), params: { url: "https://example.com/pack" }, headers: headers }
    include_examples "retired buildpacks endpoint"
  end

  describe "PUT /buildpacks" do
    before { put api_v1_app_buildpacks_path(app_record), params: { urls: [ "https://example.com/pack" ] }, headers: headers }
    include_examples "retired buildpacks endpoint"
  end

  describe "DELETE /buildpacks" do
    before { delete api_v1_app_buildpacks_path(app_record), headers: headers }
    include_examples "retired buildpacks endpoint"
  end

  it "returns 401 without token" do
    get api_v1_app_buildpacks_path(app_record)
    expect(response).to have_http_status(:unauthorized)
  end
end
