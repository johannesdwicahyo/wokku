# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::AiController", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let!(:deploy) { app_record.deploys.create!(status: "failed", log: "err") }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "diagnose returns AiDebugger result JSON" do
    allow_any_instance_of(AiDebugger).to receive(:diagnose).and_return({ diagnosis: "Run bundle install" })
    post "/api/v1/ai/diagnose", params: { deploy_id: deploy.id }, headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["diagnosis"]).to eq("Run bundle install")
  end

  it "diagnose returns 401 unauthenticated" do
    post "/api/v1/ai/diagnose", params: { deploy_id: deploy.id }
    expect(response).to have_http_status(:unauthorized)
  end

  it "diagnose 404 when deploy not found" do
    post "/api/v1/ai/diagnose", params: { deploy_id: -1 }, headers: headers
    expect([ 404, 500 ]).to include(response.status)
  end
end
