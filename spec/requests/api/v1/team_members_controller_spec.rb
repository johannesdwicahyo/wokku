# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::TeamMembersController", type: :request do
  let(:user) { users(:one) }
  let(:team) { teams(:one) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "index returns team memberships" do
    get "/api/v1/teams/#{team.id}/members", headers: headers
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body.any? { |m| m["email"] == user.email }).to be_truthy
  end

  it "create adds an existing user as team member" do
    new_user = User.create!(email: "newmember@example.com", password: "password123456")
    expect {
      post "/api/v1/teams/#{team.id}/members",
        params: { email: new_user.email, role: "member" },
        headers: headers
    }.to change { team.team_memberships.count }.by(1)
    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["email"]).to eq(new_user.email)
    expect(body["role"]).to eq("member")
  end

  it "create returns 404 when user email does not exist" do
    post "/api/v1/teams/#{team.id}/members",
      params: { email: "nobody@example.com", role: "member" },
      headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "create returns 422 when membership invalid (duplicate)" do
    post "/api/v1/teams/#{team.id}/members",
      params: { email: user.email, role: "member" },
      headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "destroy removes a team membership" do
    new_user = User.create!(email: "drop@example.com", password: "password123456")
    tm = TeamMembership.create!(user: new_user, team: team, role: :member)

    expect {
      delete "/api/v1/teams/#{team.id}/members/#{tm.id}", headers: headers
    }.to change { team.team_memberships.count }.by(-1)
    expect(response).to have_http_status(:success)
  end

  describe "foreign team" do
    let(:owner) { User.create!(email: "tm-foreign@example.com", password: "password123456") }
    let(:foreign_team) { Team.create!(name: "tm-foreign", owner: owner).tap { |t| TeamMembership.create!(user: owner, team: t, role: :admin) } }

    it "index returns 404 for a team the caller is not in" do
      get "/api/v1/teams/#{foreign_team.id}/members", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "destroy returns 404 and keeps the membership for a foreign team" do
      tm = foreign_team.team_memberships.first
      delete "/api/v1/teams/#{foreign_team.id}/members/#{tm.id}", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(TeamMembership.exists?(tm.id)).to be(true)
    end
  end
end
