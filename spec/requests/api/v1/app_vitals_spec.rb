require "rails_helper"

RSpec.describe "GET /api/v1/apps/:id/vitals", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }
  let(:payload) { { app_id: app_record.id, window_days: 7, latest: {}, history: {} } }

  before { allow(::Api::V1::Serializers::AppVitals).to receive(:new).and_return(double(call: payload)) }

  it "returns 200 + payload" do
    get "/api/v1/apps/#{app_record.id}/vitals", headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["window_days"]).to eq(7)
  end

  it "returns 401 without a token" do
    get "/api/v1/apps/#{app_record.id}/vitals"
    expect(response).to have_http_status(:unauthorized)
  end
end
