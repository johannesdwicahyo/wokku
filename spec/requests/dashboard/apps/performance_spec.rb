require "rails_helper"

RSpec.describe "Dashboard::Apps::Performance", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:one) }
  let(:app_record) { app_records(:one) }

  before { sign_in user }

  describe "GET /dashboard/apps/:app_id/performance" do
    it "renders the empty state when no rollups exist" do
      get dashboard_app_performance_path(app_record)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("v.js?t=")
      expect(response.body).to include(app_record.reload.vitals_ingest_token)
    end

    it "renders metric cards when rollups exist" do
      VitalsHourlyRollup.create!(
        app_record: app_record, bucketed_at: 1.hour.ago.beginning_of_hour, metric: "LCP",
        p50: 100, p75: 200, p95: 400, sample_count: 12
      )
      get dashboard_app_performance_path(app_record)
      expect(response.body).to include("LCP")
      expect(response.body).to include("200") # p75
    end
  end

  describe "POST /dashboard/apps/:app_id/performance/rotate_token" do
    it "rotates the token and redirects back" do
      app_record.ensure_vitals_ingest_token!
      old = app_record.reload.vitals_ingest_token
      post rotate_token_dashboard_app_performance_path(app_record)
      expect(app_record.reload.vitals_ingest_token).not_to eq(old)
      expect(response).to redirect_to(dashboard_app_performance_path(app_record))
    end
  end

  describe "without authentication" do
    it "redirects to sign-in" do
      sign_out user
      get dashboard_app_performance_path(app_record)
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
