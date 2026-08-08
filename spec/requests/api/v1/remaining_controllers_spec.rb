# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1 remaining controllers (smoke)", type: :request do
  describe "DomainsController" do
    let(:user) { User.create!(email: "domains-test@example.com", password: "password123456") }
    let(:team) { Team.create!(name: "Domains Team", owner: user).tap { |t| TeamMembership.create!(user: user, team: t, role: :admin) } }
    let(:server) { Server.create!(name: "prod", host: "1.2.3.4", team: team) }
    let(:app_record) { AppRecord.create!(name: "myapp", server: server, team: team, creator: user) }
    let!(:domain) { Domain.create!(hostname: "myapp.example.com", app_record: app_record) }
    let(:plain_token) { api_v1_token_for(user) }
    let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

    it "index returns domains for app" do
      get api_v1_app_domains_path(app_record), headers: headers
      expect(response).to have_http_status(:success)
      domains = JSON.parse(response.body)
      expect(domains.length).to eq(1)
      expect(domains.first["hostname"]).to eq("myapp.example.com")
    end
  end

  describe "DatabasesController" do
    let(:user) { User.create!(email: "db-test@example.com", password: "password123456") }
    let(:team) { Team.create!(name: "DB Team", owner: user).tap { |t| TeamMembership.create!(user: user, team: t, role: :admin) } }
    let(:server) { Server.create!(name: "prod", host: "1.2.3.4", team: team) }
    let!(:database) { DatabaseService.create!(name: "mydb", service_type: "postgres", server: server) }
    let(:plain_token) { api_v1_token_for(user) }
    let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

    it "index returns user's databases" do
      get api_v1_databases_path, headers: headers
      expect(response).to have_http_status(:success)
      dbs = JSON.parse(response.body)
      expect(dbs.length).to eq(1)
      expect(dbs.first["name"]).to eq("mydb")
    end

    it "show returns database details" do
      get api_v1_database_path(database), headers: headers
      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body["service_type"]).to eq("postgres")
    end

    it "index returns 401 without token" do
      get api_v1_databases_path
      expect(response).to have_http_status(:unauthorized)
    end

    it "show returns 401 without token" do
      get api_v1_database_path(database)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "ReleasesController" do
    let(:user) { User.create!(email: "releases-test@example.com", password: "password123456") }
    let(:team) { Team.create!(name: "Releases Team", owner: user).tap { |t| TeamMembership.create!(user: user, team: t, role: :admin) } }
    let(:server) { Server.create!(name: "prod", host: "1.2.3.4", team: team) }
    let(:app_record) { AppRecord.create!(name: "myapp", server: server, team: team, creator: user) }
    let!(:release) { Release.create!(app_record: app_record, description: "Initial release") }
    let(:plain_token) { api_v1_token_for(user) }
    let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

    it "index returns releases for app" do
      get api_v1_app_releases_path(app_record), headers: headers
      expect(response).to have_http_status(:success)
      releases = JSON.parse(response.body)
      expect(releases.length).to eq(1)
    end

    it "show returns release details" do
      get api_v1_app_release_path(app_record, release), headers: headers
      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body["version"]).to eq(1)
    end
  end

  describe "SshKeysController" do
    let(:user) { User.create!(email: "ssh-test@example.com", password: "password123456") }
    let(:plain_token) { api_v1_token_for(user) }
    let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

    it "index returns user's ssh keys" do
      get api_v1_ssh_keys_path, headers: headers
      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)).to eq([])
    end
  end

  describe "TeamsController" do
    let(:user) { User.create!(email: "teams-test@example.com", password: "password123456") }
    let!(:team) { Team.create!(name: "My Team", owner: user).tap { |t| TeamMembership.create!(user: user, team: t, role: :admin) } }
    let(:plain_token) { api_v1_token_for(user) }
    let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

    it "index returns user's teams" do
      get api_v1_teams_path, headers: headers
      expect(response).to have_http_status(:success)
      teams_body = JSON.parse(response.body)
      expect(teams_body.length).to eq(1)
      expect(teams_body.first["name"]).to eq("My Team")
    end

    it "create creates a new team" do
      post api_v1_teams_path, params: { name: "New Team" }, headers: headers
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["name"]).to eq("New Team")
    end
  end

  describe "TeamMembersController (isolated)" do
    let(:user) { User.create!(email: "tm-test@example.com", password: "password123456") }
    let!(:team) { Team.create!(name: "Members Team", owner: user) }
    let!(:membership) { TeamMembership.create!(user: user, team: team, role: :admin) }
    let(:plain_token) { api_v1_token_for(user) }
    let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

    it "index returns team members" do
      get api_v1_team_members_path(team), headers: headers
      expect(response).to have_http_status(:success)
      members = JSON.parse(response.body)
      expect(members.length).to eq(1)
      expect(members.first["email"]).to eq(user.email)
    end
  end

  describe "NotificationsController" do
    let(:user) { User.create!(email: "notif-test@example.com", password: "password123456") }
    let(:team) { Team.create!(name: "Notif Team", owner: user).tap { |t| TeamMembership.create!(user: user, team: t, role: :admin) } }
    let!(:notification) do
      Notification.create!(
        team: team,
        channel: :email,
        events: [ "deploy" ],
        config: { email: "alert@example.com" }
      )
    end
    let(:plain_token) { api_v1_token_for(user) }
    let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

    it "index returns user's notifications" do
      get api_v1_notifications_path, headers: headers
      expect(response).to have_http_status(:success)
      notifications = JSON.parse(response.body)
      expect(notifications.length).to eq(1)
    end

    it "destroy removes notification" do
      delete api_v1_notification_path(notification), headers: headers
      expect(response).to have_http_status(:success)
      expect(Notification.exists?(notification.id)).to be(false)
    end
  end

  describe "PsController" do
    let(:user) { User.create!(email: "ps-test@example.com", password: "password123456") }
    let(:team) { Team.create!(name: "PS Team", owner: user).tap { |t| TeamMembership.create!(user: user, team: t, role: :admin) } }
    let(:server) { Server.create!(name: "prod", host: "1.2.3.4", team: team) }
    let(:app_record) { AppRecord.create!(name: "myapp", server: server, team: team, creator: user) }
    let(:plain_token) { api_v1_token_for(user) }
    let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

    it "show returns process info" do
      get api_v1_app_ps_path(app_record), headers: headers
      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body).to have_key("processes")
    end
  end

  describe "LogsController (remaining)" do
    let(:user) { users(:one) }
    let(:app_record) { app_records(:one) }
    let(:plain_token) { api_v1_token_for(user, name: "logs-remaining-test-#{SecureRandom.hex(4)}") }
    let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

    it "index returns app logs" do
      allow(Apps::LogReader).to receive(:recent).and_return("2026-03-13 log line 1\n2026-03-13 log line 2")

      get api_v1_app_logs_path(app_record), headers: headers
      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body).to have_key("logs")
    end
  end
end
