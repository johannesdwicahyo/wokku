# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/apps/:id/transfer", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }
  let(:transferrer) { instance_double(::Apps::Lifecycle::Transferrer) }
  let(:to_user) { instance_double("User", email: "to@example.com") }
  let(:transfer_obj) { instance_double("AppTransfer", id: "t-id", to_user: to_user, expires_at: 7.days.from_now) }

  before do
    allow(::Apps::Lifecycle::Transferrer).to receive(:new).and_return(transferrer)
    allow(transferrer).to receive(:call!).and_return(transfer_obj)
  end

  it "initiates and returns 200" do
    post "/api/v1/apps/#{app_record.id}/transfer", params: { recipient_email: "to@example.com" }.to_json, headers: headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["transfer_id"]).to eq("t-id")
    expect(body["recipient_email"]).to eq("to@example.com")
  end

  it "returns 400 on Apps::Lifecycle::Error with code: :invalid_email" do
    allow(transferrer).to receive(:call!).and_raise(::Apps::Lifecycle::Error.new("Invalid email", code: :invalid_email))
    post "/api/v1/apps/#{app_record.id}/transfer", params: { recipient_email: "x" }.to_json, headers: headers
    expect(response).to have_http_status(:bad_request)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("Invalid email")
    expect(body["error_code"]).to eq("invalid_params")
  end

  it "returns 409 on Apps::Lifecycle::Error with code: :transfer_pending" do
    allow(transferrer).to receive(:call!).and_raise(::Apps::Lifecycle::Error.new("A transfer is already pending for this app.", code: :transfer_pending))
    post "/api/v1/apps/#{app_record.id}/transfer", params: { recipient_email: "to@example.com" }.to_json, headers: headers
    expect(response).to have_http_status(:conflict)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("A transfer is already pending for this app.")
    expect(body["error_code"]).to eq("already_exists")
  end
end
