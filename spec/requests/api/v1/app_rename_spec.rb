# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PATCH /api/v1/apps/:id/rename", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }
  let(:renamer) { instance_double(::Apps::Lifecycle::Renamer) }

  before do
    allow(::Apps::Lifecycle::Renamer).to receive(:new).and_return(renamer)
    allow(renamer).to receive(:call!).and_return(app_record.tap { |a| a.name = "renamed" })
  end

  it "renames and returns 200" do
    patch "/api/v1/apps/#{app_record.id}/rename", params: { name: "renamed" }.to_json, headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("name" => "renamed")
  end

  it "returns 400 on Apps::Lifecycle::Error with the default (unmapped) code" do
    allow(renamer).to receive(:call!).and_raise(::Apps::Lifecycle::Error.new("Invalid name"))
    patch "/api/v1/apps/#{app_record.id}/rename", params: { name: "BAD" }.to_json, headers: headers
    expect(response).to have_http_status(:bad_request)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("Invalid name")
    expect(body["error_code"]).to eq("invalid_params")
  end

  it "returns 400 on Apps::Lifecycle::Error with code: :invalid_name" do
    allow(renamer).to receive(:call!).and_raise(::Apps::Lifecycle::Error.new("Invalid app name", code: :invalid_name))
    patch "/api/v1/apps/#{app_record.id}/rename", params: { name: "BAD" }.to_json, headers: headers
    expect(response).to have_http_status(:bad_request)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("Invalid app name")
    expect(body["error_code"]).to eq("invalid_params")
  end

  it "returns 401 without a token" do
    patch "/api/v1/apps/#{app_record.id}/rename", params: { name: "x" }.to_json, headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end
end
