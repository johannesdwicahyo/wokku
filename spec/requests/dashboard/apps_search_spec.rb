require "rails_helper"

RSpec.describe "Dashboard::Apps#search", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user) }
  let!(:server) { create(:server) }
  let(:team) do
    t = Team.create!(name: "search-team-#{SecureRandom.hex(3)}", owner: user)
    TeamMembership.create!(team: t, user: user, role: :admin)
    t
  end

  before { sign_in user }

  it "returns JSON of matching apps (session-authed)" do
    create(:app_record, name: "wicara-ai",    team: team, creator: user, server: server)
    create(:app_record, name: "wicara-rails", team: team, creator: user, server: server)
    create(:app_record, name: "unrelated",    team: team, creator: user, server: server)

    get search_dashboard_apps_path, params: { q: "wicara" }, headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    names = body.map { |a| a["name"] }
    expect(names).to contain_exactly("wicara-ai", "wicara-rails")
    expect(body.first).to include("id", "name", "status", "url")
  end

  it "returns all (limit 8) when q is blank" do
    9.times { |i| create(:app_record, name: "app-#{i}", team: team, creator: user, server: server) }
    get search_dashboard_apps_path, headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).size).to eq(8)
  end

  it "does not leak other users' apps" do
    other = create(:user)
    other_team = Team.create!(name: "private-team", owner: other)
    TeamMembership.create!(team: other_team, user: other, role: :admin)
    create(:app_record, name: "private-app", team: other_team, creator: other, server: server)

    get search_dashboard_apps_path, params: { q: "private" }, headers: { "Accept" => "application/json" }
    expect(JSON.parse(response.body)).to be_empty
  end
end
