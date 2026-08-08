require "rails_helper"

RSpec.describe "GET /api/v1/apps/:id/monitor", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }
  let(:payload) { { app_id: app_record.id, totals: { req_count: 0 }, buckets: [], recent_slow: [] } }

  before { allow(::Api::V1::Serializers::AppMonitor).to receive(:new).and_return(double(call: payload)) }

  it "returns 200 + payload" do
    get "/api/v1/apps/#{app_record.id}/monitor", headers: headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["app_id"]).to eq(app_record.id)
    expect(body["totals"]["req_count"]).to eq(0)
  end

  it "returns 401 without a token" do
    get "/api/v1/apps/#{app_record.id}/monitor"
    expect(response).to have_http_status(:unauthorized)
  end
end
