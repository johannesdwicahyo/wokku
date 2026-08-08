# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/apps/:id/deploy", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }

  it "returns 409 app_locked when DeployLock reports locked" do
    allow(::Apps::Lifecycle::DeployLock).to receive(:new)
      .and_return(instance_double(::Apps::Lifecycle::DeployLock, locked?: true))
    post "/api/v1/apps/#{app_record.id}/deploy", headers: headers
    expect(response).to have_http_status(:conflict)
    body = JSON.parse(response.body)
    expect(body["error"]).to match(/locked/i)
    expect(body["error_code"]).to eq("app_locked")
  end
end
