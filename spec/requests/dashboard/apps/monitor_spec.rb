require "rails_helper"

RSpec.describe "Dashboard::Apps::Monitor", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }

  before { sign_in user }

  describe "GET /dashboard/apps/:app_id/monitor" do
    it "renders the page with the empty-state banner when no buckets exist" do
      get dashboard_app_monitor_path(app_record)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("no request data yet")
    end

    it "renders stat tiles when aggregates exist" do
      RequestAggregate.create!(
        app_record: app_record,
        bucket_start: 10.minutes.ago,
        req_count: 120, p50_ms: 30, p95_ms: 180,
        error_4xx: 3, error_5xx: 1, bytes_sent_total: 50_000
      )
      get dashboard_app_monitor_path(app_record)
      expect(response).to have_http_status(:ok)
      # rpm = 120 / (24h*60min) ≈ 0.1 — just check the tile labels exist
      expect(response.body).to include("Req / minute")
      expect(response.body).to include("p95 latency")
      expect(response.body).to include("Error rate")
    end

    it "renders the slow-requests table when samples exist" do
      RequestSample.create!(
        server: app_record.server, app_record: app_record, ts: 5.minutes.ago,
        method: "GET", path: "/api/slow", status: 200, response_time_ms: 1500,
        bytes_sent: 500, remote_addr: "1.2.3.4"
      )
      get dashboard_app_monitor_path(app_record)
      expect(response.body).to include("/api/slow")
      expect(response.body).to include("1500ms")
    end
  end

  describe "without authentication" do
    it "redirects to sign-in" do
      sign_out user
      get dashboard_app_monitor_path(app_record)
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
