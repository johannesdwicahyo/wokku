# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::LogsController", type: :request do
  let(:user) { User.create!(email: "logs-test@example.com", password: "password123456") }
  let(:team) do
    t = Team.create!(name: "Logs Test Team", owner: user)
    TeamMembership.create!(user: user, team: t, role: :admin)
    t
  end
  let(:server) { Server.create!(name: "prod", host: "1.2.3.4", team: team) }
  let!(:app_record) { AppRecord.create!(name: "myapp", server: server, team: team, creator: user) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  def seed_logs(*lines, at: 1.hour.ago)
    rows = lines.each_with_index.map do |(line, level), i|
      {
        server_id: server.id, app_record_id: app_record.id,
        container: "#{app_record.name}.web.1",
        ts: at + i.seconds, level: (level || "info"),
        line: line, ingested_at: Time.current
      }
    end
    Log.insert_all(rows)
  end

  it "GET /apps/:id/logs?follow=1 streams chunks as text/plain" do
    allow(Apps::LogReader).to receive(:tail).and_yield("hello\n").and_yield("world\n")

    get api_v1_app_logs_url(app_record), params: { follow: 1 }, headers: headers
    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq("text/plain")
    expect(response.body).to match(/hello/)
    expect(response.body).to match(/world/)
  end

  describe "GET /apps/:id/logs (durable-first)" do
    it "returns persisted logs with source: durable" do
      seed_logs([ "GET / 200" ], [ "GET /health 200" ])

      get api_v1_app_logs_url(app_record), headers: headers
      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json["source"]).to eq("durable")
      expect(json["logs"].size).to eq(2)
      expect(json["logs"].first.keys).to match_array(%w[ts container level line])
      expect(json["logs"].map { |l| l["line"] }).to include("GET / 200", "GET /health 200")
    end

    it "orders logs most-recent-first" do
      seed_logs([ "older" ], at: 2.hours.ago)
      seed_logs([ "newer" ], at: 1.hour.ago)

      get api_v1_app_logs_url(app_record), headers: headers
      json = response.parsed_body
      expect(json["logs"].map { |l| l["line"] }).to eq(%w[newer older])
    end

    it "filters by since" do
      seed_logs([ "old line" ], at: 48.hours.ago)
      seed_logs([ "recent line" ], at: 1.hour.ago)

      get api_v1_app_logs_url(app_record), params: { since: 24.hours.ago.iso8601 }, headers: headers
      json = response.parsed_body
      expect(json["source"]).to eq("durable")
      lines = json["logs"].map { |l| l["line"] }
      expect(lines).to include("recent line")
      expect(lines).not_to include("old line")
    end

    it "filters by level" do
      seed_logs([ "GET / 200" ], [ "ERROR boom", "error" ])

      get api_v1_app_logs_url(app_record), params: { level: "error" }, headers: headers
      json = response.parsed_body
      lines = json["logs"].map { |l| l["line"] }
      expect(lines).to include("ERROR boom")
      expect(lines).not_to include("GET / 200")
    end

    it "filters by q (ILIKE search)" do
      seed_logs([ "GET / 200" ], [ "connection refused" ])

      get api_v1_app_logs_url(app_record), params: { q: "refused" }, headers: headers
      json = response.parsed_body
      lines = json["logs"].map { |l| l["line"] }
      expect(lines).to include("connection refused")
      expect(lines).not_to include("GET / 200")
    end

    it "clamps lines to 1000 max" do
      seed_logs([ "GET / 200" ])

      get api_v1_app_logs_url(app_record), params: { lines: 5000 }, headers: headers
      expect(response).to have_http_status(:success)
      expect(response.parsed_body["source"]).to eq("durable")
    end

    it "falls back to SSH live tail when durable is empty and no explicit since" do
      allow(Apps::LogReader).to receive(:recent).and_return("hello from ssh")

      get api_v1_app_logs_url(app_record), headers: headers
      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json["source"]).to eq("live")
      expect(json["logs"]).to eq("hello from ssh")
    end

    it "does NOT fall back to SSH when an explicit since is given and durable is empty" do
      expect(Apps::LogReader).not_to receive(:recent)

      get api_v1_app_logs_url(app_record), params: { since: 1.hour.ago.iso8601 }, headers: headers
      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json["source"]).to eq("durable")
      expect(json["logs"]).to eq([])
    end

    it "does NOT fall back to SSH when a filter is applied and durable has no matches" do
      expect(Apps::LogReader).not_to receive(:recent)

      get api_v1_app_logs_url(app_record), params: { level: "error" }, headers: headers
      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json["source"]).to eq("durable")
      expect(json["logs"]).to eq([])
    end

    it "returns 400 invalid_time for an unparseable since" do
      get api_v1_app_logs_url(app_record), params: { since: "not-a-time" }, headers: headers
      expect(response).to have_http_status(:bad_request)
      json = response.parsed_body
      expect(json["error_code"]).to eq("invalid_time")
      expect(json["hint"]).to be_present
    end

    it "returns 400 invalid_time for an unparseable until" do
      get api_v1_app_logs_url(app_record), params: { until: "not-a-time" }, headers: headers
      expect(response).to have_http_status(:bad_request)
      json = response.parsed_body
      expect(json["error_code"]).to eq("invalid_time")
    end
  end
end
