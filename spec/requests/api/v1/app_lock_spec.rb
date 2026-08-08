# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/apps/:id/lock", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }
  let(:lock) { instance_double(::Apps::Lifecycle::DeployLock, lock!: true) }

  before { allow(::Apps::Lifecycle::DeployLock).to receive(:new).and_return(lock) }

  it "locks and returns 200" do
    post "/api/v1/apps/#{app_record.id}/lock", params: "{}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("locked" => true)
  end

  it "returns 400 on Apps::Lifecycle::Error with the default (unmapped) code" do
    allow(lock).to receive(:lock!).and_raise(::Apps::Lifecycle::Error.new("nope"))
    post "/api/v1/apps/#{app_record.id}/lock", params: "{}", headers: headers
    expect(response).to have_http_status(:bad_request)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("nope")
    expect(body["error_code"]).to eq("invalid_params")
  end

  it "returns 401 without a token" do
    post "/api/v1/apps/#{app_record.id}/lock", params: "{}", headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end
end
