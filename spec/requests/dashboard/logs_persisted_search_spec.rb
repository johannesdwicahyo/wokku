require "rails_helper"

RSpec.describe "Dashboard::Logs persisted-search", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)    { users(:one) }
  let(:app_rec) { app_records(:one) }
  let(:server)  { app_rec.server }

  before { sign_in user }

  def seed_logs(*lines, at: 1.hour.ago)
    rows = lines.each_with_index.map do |(line, level), i|
      {
        server_id: server.id, app_record_id: app_rec.id,
        container: "#{app_rec.name}.web.1",
        ts: at + i.seconds, level: (level || "info"),
        line: line, ingested_at: Time.current
      }
    end
    Log.insert_all(rows)
  end

  # All log-content assertions use ?deferred=1 because the log lines are
  # rendered inside the lazy turbo-frame fragment, not the shell.
  describe "GET /dashboard/apps/:id/logs?deferred=1" do
    it "falls back to SSH live tail when no persisted logs exist" do
      allow(Apps::LogReader).to receive(:recent).and_return("hello from ssh")
      get dashboard_app_logs_path(app_rec, deferred: 1)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("hello from ssh")
    end

    it "renders persisted logs when present" do
      seed_logs([ "GET / 200" ], [ "GET /health 200" ])
      get dashboard_app_logs_path(app_rec, deferred: 1)
      expect(response.body).to include("GET / 200")
      expect(response.body).to include("GET /health 200")
    end

    it "filters by ILIKE search query" do
      seed_logs([ "GET / 200" ], [ "ERROR connection refused", "error" ])
      get dashboard_app_logs_path(app_rec, deferred: 1, q: "ERROR")
      expect(response.body).to include("connection refused")
      expect(response.body).not_to include("GET / 200")
    end

    it "filters by level" do
      seed_logs([ "GET / 200" ], [ "ERROR connection refused", "error" ])
      get dashboard_app_logs_path(app_rec, deferred: 1, level: "error")
      expect(response.body).to include("connection refused")
      expect(response.body).not_to include("GET / 200")
    end

    it "respects since/until time bounds" do
      seed_logs([ "old line" ], at: 48.hours.ago)
      seed_logs([ "recent line" ], at: 1.hour.ago)
      get dashboard_app_logs_path(app_rec, deferred: 1) # default since = 24h ago
      expect(response.body).to include("recent line")
      expect(response.body).not_to include("old line")
    end

    it "shows the SSH tail when source=live even if persisted logs exist" do
      seed_logs([ "persisted line" ])
      allow(Apps::LogReader).to receive(:recent).and_return("ssh live tail line")
      get dashboard_app_logs_path(app_rec, deferred: 1, source: "live")
      expect(response.body).to include("ssh live tail line")
    end
  end
end
