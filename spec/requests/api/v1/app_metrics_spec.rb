require "rails_helper"

RSpec.describe "GET /api/v1/apps/:id/metrics", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }
  let(:payload) { { app_id: app_record.id, minute: [], hourly: [] } }

  before { allow(::Api::V1::Serializers::AppMetrics).to receive(:new).and_return(double(call: payload)) }

  it "returns 200 + serializer payload" do
    get "/api/v1/apps/#{app_record.id}/metrics", headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("app_id" => app_record.id, "minute" => [], "hourly" => [])
  end

  it "returns 401 without a token" do
    get "/api/v1/apps/#{app_record.id}/metrics"
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 404 for an unknown app" do
    get "/api/v1/apps/no-such-app/metrics", headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
