# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/apps/:id/unlock", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }
  let(:lock) { instance_double(::Apps::Lifecycle::DeployLock, unlock!: false) }

  before { allow(::Apps::Lifecycle::DeployLock).to receive(:new).and_return(lock) }

  it "unlocks and returns 200" do
    post "/api/v1/apps/#{app_record.id}/unlock", params: "{}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("locked" => false)
  end

  it "returns 400 on Apps::Lifecycle::Error with the default (unmapped) code" do
    allow(lock).to receive(:unlock!).and_raise(::Apps::Lifecycle::Error.new("nope"))
    post "/api/v1/apps/#{app_record.id}/unlock", params: "{}", headers: headers
    expect(response).to have_http_status(:bad_request)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("nope")
    expect(body["error_code"]).to eq("invalid_params")
  end
end
