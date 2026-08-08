# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::ActivitiesController", type: :request do
  let(:user) { users(:one) }
  let(:team) { teams(:one) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "index returns activities for the user's team" do
    Activity.create!(team: team, user: user, action: "app.created", target_name: "x", target_type: "AppRecord", target_id: 1)

    get "/api/v1/activities", headers: headers
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body).to be_a(Array)
    expect(body.any? { |a| a["action"] == "app.created" }).to be_truthy
  end

  it "index respects limit param clamped to [1, 200]" do
    3.times do |i|
      Activity.create!(team: team, user: user, action: "x#{i}", target_name: "x", target_type: "AppRecord", target_id: i + 1)
    end

    get "/api/v1/activities", params: { limit: 2 }, headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body).length).to eq(2)
  end

  it "unauth returns 401" do
    get "/api/v1/activities"
    expect(response).to have_http_status(:unauthorized)
  end
end
