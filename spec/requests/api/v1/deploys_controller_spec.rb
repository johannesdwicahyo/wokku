# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::DeploysController", type: :request do
  let(:user) { User.create!(email: "deploys-test@example.com", password: "password123456") }
  let(:team) do
    t = Team.create!(name: "Deploys Team", owner: user)
    TeamMembership.create!(user: user, team: t, role: :admin)
    t
  end
  let(:server) { Server.create!(name: "prod", host: "1.2.3.4", team: team) }
  let!(:app_record) { AppRecord.create!(name: "myapp", server: server, team: team, creator: user) }
  let!(:deploy) { Deploy.create!(app_record: app_record, status: :succeeded, commit_sha: "abc1234") }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "index returns 401 without token" do
    get api_v1_app_deploys_path(app_record)
    expect(response).to have_http_status(:unauthorized)
  end

  it "show returns 401 without token" do
    get api_v1_app_deploy_path(app_record, deploy)
    expect(response).to have_http_status(:unauthorized)
  end

  it "index returns deploys for app" do
    get api_v1_app_deploys_path(app_record), headers: headers
    expect(response).to have_http_status(:success)
    deploys = JSON.parse(response.body)
    expect(deploys).to be_a(Array)
    expect(deploys.length).to eq(1)
    expect(deploys.first["status"]).to eq("succeeded")
  end

  it "show returns deploy details" do
    get api_v1_app_deploy_path(app_record, deploy), headers: headers
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body["id"]).to eq(deploy.id)
    expect(body["status"]).to eq("succeeded")
    expect(body["commit_sha"]).to eq("abc1234")
  end

  it "non-team member cannot list deploys" do
    other_user = User.create!(email: "other-deploys@example.com", password: "password123456")
    other_token = api_v1_token_for(other_user)
    get api_v1_app_deploys_path(app_record), headers: { "Authorization" => "Bearer #{other_token}" }
    expect(response).to have_http_status(:not_found)
  end
end
