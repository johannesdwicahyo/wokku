require "rails_helper"

RSpec.describe "GET /api/v1/databases/:id/monitor", type: :request do
  let(:user) { users(:one) }
  let(:database) { database_services(:one) rescue DatabaseService.first || skip("no DatabaseService fixture") }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }
  let(:payload) { { database_id: database.id, recorded_at: nil, top_queries: [] } }

  before do
    allow(::Api::V1::Serializers::DatabaseMonitor).to receive(:new).and_return(double(call: payload))
  end

  it "returns 200 + payload" do
    get "/api/v1/databases/#{database.id}/monitor", headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["database_id"]).to eq(database.id)
  end

  it "returns 401 without a token" do
    get "/api/v1/databases/#{database.id}/monitor"
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 404 for an unknown database" do
    get "/api/v1/databases/00000000-0000-0000-0000-000000000000/monitor", headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
