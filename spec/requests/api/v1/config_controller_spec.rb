# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::ConfigController", type: :request do
  let(:user) { User.create!(email: "test@example.com", password: "password123456") }
  let(:team) do
    t = Team.create!(name: "Test Team", owner: user)
    TeamMembership.create!(user: user, team: t, role: :admin)
    t
  end
  let(:server) { Server.create!(name: "prod", host: "1.2.3.4", team: team) }
  let!(:app_record) { AppRecord.create!(name: "myapp", server: server, team: team, creator: user) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "show returns config vars from EnvVar rows — cp env truth (B6 W3)" do
    app_record.env_vars.create!(key: "DATABASE_URL", value: "postgres://localhost")
    app_record.env_vars.create!(key: "REDIS_URL", value: "redis://localhost")
    get api_v1_app_config_path(app_record), headers: headers
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body["config"]["DATABASE_URL"]).to eq("postgres://localhost")
    expect(body["config"]["REDIS_URL"]).to eq("redis://localhost")
  end

  it "destroy removes config vars" do
    app_record.env_vars.create!(key: "OLD_VAR", value: "old")
    delete api_v1_app_config_path(app_record),
      params: { keys: [ "OLD_VAR" ] },
      headers: headers
    expect(response).to have_http_status(:success)
    expect(app_record.env_vars.count).to eq(0)
  end

  it "non-team member cannot access config" do
    other_user = User.create!(email: "other@example.com", password: "password123456")
    other_token = api_v1_token_for(other_user)
    get api_v1_app_config_path(app_record), headers: { "Authorization" => "Bearer #{other_token}" }
    expect(response).to have_http_status(:forbidden)
  end
end
