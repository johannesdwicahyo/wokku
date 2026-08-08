# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/apps/:id/clone", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }
  let(:cloner) { instance_double(::Apps::Lifecycle::Cloner) }
  let(:new_app) { instance_double("AppRecord", id: "new-id", name: "cloned") }

  before do
    allow(::Apps::Lifecycle::Cloner).to receive(:new).and_return(cloner)
    allow(cloner).to receive(:call!).and_return(new_app)
  end

  it "clones with skip_deploy defaulting to true and returns 200" do
    post "/api/v1/apps/#{app_record.id}/clone", params: { name: "cloned" }.to_json, headers: headers
    expect(response).to have_http_status(:ok)
    expect(cloner).to have_received(:call!).with("cloned", skip_deploy: true)
  end

  it "respects skip_deploy=false when explicitly passed" do
    post "/api/v1/apps/#{app_record.id}/clone", params: { name: "cloned", skip_deploy: false }.to_json, headers: headers
    expect(cloner).to have_received(:call!).with("cloned", skip_deploy: false)
  end

  it "returns 400 on Apps::Lifecycle::Error with the default (unmapped) code" do
    allow(cloner).to receive(:call!).and_raise(::Apps::Lifecycle::Error.new("Name taken"))
    post "/api/v1/apps/#{app_record.id}/clone", params: { name: "cloned" }.to_json, headers: headers
    expect(response).to have_http_status(:bad_request)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("Name taken")
    expect(body["error_code"]).to eq("invalid_params")
  end

  it "returns 409 on Apps::Lifecycle::Error with code: :name_taken" do
    allow(cloner).to receive(:call!).and_raise(::Apps::Lifecycle::Error.new("Name already taken on this server", code: :name_taken))
    post "/api/v1/apps/#{app_record.id}/clone", params: { name: "cloned" }.to_json, headers: headers
    expect(response).to have_http_status(:conflict)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("Name already taken on this server")
    expect(body["error_code"]).to eq("already_exists")
  end
end
