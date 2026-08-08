# frozen_string_literal: true

require "rails_helper"

# W7 Phase 2: dokku checks are dead — apps run on Swarm, health is
# platform-supervised. Routes stay; show returns the typed supervised
# shape, update refuses (mirrors Dashboard::ChecksController).
RSpec.describe "API::V1::ChecksController", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "show returns the Swarm-supervised checks shape (no SSH)" do
    get "/api/v1/apps/#{app_record.id}/checks", headers: headers
    expect(response).to have_http_status(:success)
    checks = JSON.parse(response.body)["checks"]
    expect(checks["supervised"]).to be(true)
    expect(checks["runtime"]).to eq("swarm")
    expect(checks["message"]).to match(/Swarm runtime/)
  end

  it "update refuses with the Swarm-managed message" do
    put "/api/v1/apps/#{app_record.id}/checks", params: { enabled: "true" }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["message"]).to match(/Swarm runtime/)
  end

  it "show requires a token" do
    get "/api/v1/apps/#{app_record.id}/checks"
    expect(response).to have_http_status(:unauthorized)
  end
end
