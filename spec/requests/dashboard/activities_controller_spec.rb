# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Activities", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }
  let(:team) { user.teams.first }

  before { sign_in user }

  def log(action:, channel: "app", target_name: nil, created_at: Time.current)
    Activity.create!(
      user: user, team: team, action: action,
      target_name: target_name,
      metadata: { channel: channel },
      created_at: created_at
    )
  end

  describe "GET /dashboard/activities" do
    it "redirects when not authenticated" do
      sign_out user
      get "/dashboard/activities"
      expect(response).to have_http_status(:redirect)
    end

    it "returns 200 with an empty state for a quiet team" do
      get "/dashboard/activities"
      expect(response).to have_http_status(:success)
    end

    it "filters by action" do
      keep = log(action: "app.deployed", target_name: "x")
      drop = log(action: "app.restarted", target_name: "y")
      get "/dashboard/activities", params: { action_eq: "app.deployed" }
      expect(response.body).to include(keep.target_name)
      expect(response.body).not_to include("restarted app")
    end

    it "filters by channel (metadata.channel)" do
      log(action: "app.deployed", channel: "cli", target_name: "cli-app")
      log(action: "app.deployed", channel: "app", target_name: "ui-app")
      get "/dashboard/activities", params: { channel: "cli" }
      expect(response.body).to include("cli-app")
      expect(response.body).not_to include("ui-app")
    end

    it "filters by user_id" do
      other = users(:two)
      team.team_memberships.find_or_create_by!(user: other) { |m| m.role = :member }
      keep = log(action: "app.deployed", target_name: "mine")
      Activity.create!(user: other, team: team, action: "app.deployed",
                       target_name: "theirs", metadata: { channel: "app" })
      get "/dashboard/activities", params: { user_id: user.id }
      expect(response.body).to include("mine")
      expect(response.body).not_to include("theirs")
    end

    it "filters by since date" do
      log(action: "app.deployed", target_name: "fresh", created_at: 1.hour.ago)
      log(action: "app.deployed", target_name: "stale", created_at: 5.days.ago)
      get "/dashboard/activities", params: { since: 2.days.ago.to_date.iso8601 }
      expect(response.body).to include("fresh")
      expect(response.body).not_to include("stale")
    end
  end

  describe "GET /dashboard/activities.csv" do
    it "streams a CSV with action + channel columns" do
      log(action: "app.deployed", channel: "git_push", target_name: "chat-bot")
      get "/dashboard/activities.csv"
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("action")
      expect(response.body).to include("app.deployed")
      expect(response.body).to include("git_push")
    end

    it "honors filter params on the CSV path" do
      log(action: "app.deployed", target_name: "deployed-app")
      log(action: "app.restarted", target_name: "restarted-app")
      get "/dashboard/activities.csv", params: { action_eq: "app.deployed" }
      expect(response.body).to include("deployed-app")
      expect(response.body).not_to include("restarted-app")
    end
  end

  describe "tamper-evidence banner" do
    it "shows verified state when an ActivityDigest exists" do
      ActivityDigest.create!(date: Date.current, row_count: 1,
                             chain_hash: "a" * 64, prev_hash: nil,
                             min_activity_id: 1, max_activity_id: 1)
      get "/dashboard/activities"
      expect(response.body).to include("verified")
      expect(response.body).to include("chain hash verified")
    end

    it "shows pending state when no digest yet" do
      get "/dashboard/activities"
      expect(response.body).to include("digest chain not yet built")
    end
  end
end
