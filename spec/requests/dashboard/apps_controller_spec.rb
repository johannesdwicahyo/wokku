# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Apps", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }

  it "redirects to login when not authenticated" do
    get "/dashboard/apps"
    expect(response).to have_http_status(:redirect)
  end

  it "shows the apps index when authenticated" do
    sign_in user
    get "/dashboard/apps"
    expect(response).to have_http_status(:success)
  end

  describe "GET check_name" do
    before { sign_in users(:one) }

    it "returns available true for an unused name" do
      get check_name_dashboard_apps_path, params: { name: "totally-fresh-name" }
      body = JSON.parse(response.body)
      expect(body["available"]).to be_truthy
      expect(body["name"]).to eq("totally-fresh-name")
    end

    it "returns taken with suggestions for an existing name" do
      get check_name_dashboard_apps_path, params: { name: app_records(:one).name }
      body = JSON.parse(response.body)
      expect(body["available"]).to be_falsey
      expect(body["reason"]).to eq("taken")
      expect(body["suggestions"]).to be_a(Array)
      expect(body["suggestions"]).not_to be_empty
    end

    it "flags invalid format" do
      get check_name_dashboard_apps_path, params: { name: "1bad" }
      body = JSON.parse(response.body)
      expect(body["available"]).to be_falsey
      expect(body["reason"]).to eq("invalid")
    end

    it "auto-sanitizes friendly typos and returns the cleaned name" do
      get check_name_dashboard_apps_path, params: { name: "My Cool App!" }
      body = JSON.parse(response.body)
      expect(body["available"]).to be_truthy
      expect(body["name"]).to eq("mycoolapp")
    end
  end

  # Turbo-frame sub-requests on the app show page. They each do their own
  # SSH round-trip; these tests stub the fetches to verify the partial
  # renders + the enclosing turbo_frame_tag is present.
  describe "Turbo Frame sub-requests on show" do
    let(:app_record) { app_records(:two) }

    before { sign_in users(:two) }

    it "renders runtime_metrics_frame with empty stats" do
      allow_any_instance_of(Dashboard::AppsController).to receive(:fetch_container_stats).and_return([])
      get runtime_metrics_frame_dashboard_app_path(app_record)
      expect(response).to have_http_status(:success)
      expect(response.body).to match(/runtime_metrics/)
    end

    it "renders live_logs_frame with empty logs + processes" do
      allow_any_instance_of(Dashboard::AppsController).to receive(:fetch_processes).and_return([])
      allow_any_instance_of(Dashboard::AppsController).to receive(:fetch_logs).and_return([])
      get live_logs_frame_dashboard_app_path(app_record)
      expect(response).to have_http_status(:success)
      expect(response.body).to match(/live_logs/)
    end

    it "renders resource_limits_frame with empty resources" do
      allow_any_instance_of(Dashboard::AppsController).to receive(:fetch_resources).and_return({})
      get resource_limits_frame_dashboard_app_path(app_record)
      expect(response).to have_http_status(:success)
    end
  end
end
