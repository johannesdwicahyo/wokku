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

  it "diagnose returns 404 for another team's deploy" do
    owner = User.create!(email: "ai-foreign-req@example.com", password: "password123456")
    team = Team.create!(name: "ai-foreign-req", owner: owner).tap { |t| TeamMembership.create!(user: owner, team: t, role: :admin) }
    server = Server.create!(name: "ai-foreign-req", host: "9.9.9.9", team: team)
    foreign = AppRecord.create!(name: "ai-foreign-req-app", server: server, team: team, creator: owner)
    foreign_deploy = foreign.deploys.create!(status: "failed", log: "err")
    expect_any_instance_of(AiDebugger).not_to receive(:diagnose)
    post "/api/v1/ai/diagnose", params: { deploy_id: foreign_deploy.id }, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  {
    ai_unavailable: 503,
    no_deploy_log: 422,
    ai_provider_failed: 502
  }.each do |code, status|
    it "diagnose maps AiDebugger error_code #{code.inspect} to #{status}" do
      allow_any_instance_of(AiDebugger).to receive(:diagnose)
        .and_return({ error: "boom secret-detail", error_code: code })
      post "/api/v1/ai/diagnose", params: { deploy_id: deploy.id }, headers: headers
      expect(response).to have_http_status(status)
      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq(code.to_s)
      expect(body["error"]).not_to include("secret-detail")
    end
  end
end
