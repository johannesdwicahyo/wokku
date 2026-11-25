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

  describe "GET index — instant shell" do
    before { sign_in users(:one) }

    it "renders the deferred section placeholders with lazy frames" do
      get "/dashboard/apps"
      expect(response).to have_http_status(:success)
      expect(response.body).to include('id="apps_list"')
      expect(response.body).to include('loading="lazy"')
      expect(response.body).to include(sections_dashboard_apps_path(section: :list))
      expect(response.body).to include(sections_dashboard_apps_path(section: :side))
    end

    it "renders the first-deploy chooser when the user has no apps" do
      empty_user = create(:user, :with_personal_team)
      sign_in empty_user
      get "/dashboard/apps"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("deploy()")
    end
  end

  describe "POST create — validation failure" do
    before { sign_in users(:one) }

    it "re-renders the index shell (grid, not empty-state) on invalid name" do
      # Blank name fails the presence validation; server lookup succeeds.
      post "/dashboard/apps", params: {
        app_record: { name: "", deploy_branch: "main", server_id: servers(:one).id }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      # The grid shell should render (deferred section placeholders), not the
      # zero-app empty-state chooser — because @has_apps is now set correctly.
      expect(response.body).to include('id="apps_list"')
    end
  end

  # POST create births native apps + calls Wokku.config.dns_provider to
  # create the DNS record. Which zone(s) that provider actually writes to is
  # Cloudflare::DnsProvider's job — see
  # spec/services/cloudflare/dns_provider_spec.rb.
  describe "POST create — wokkud-native births (B6 W2 flip)" do
    before do
      sign_in users(:one)
      allow(Wokku.config.dns_provider).to receive(:create_app_record)
    end

    it "births apps native + fully flagged" do
      post "/dashboard/apps", params: {
        app_record: { name: "native-born-app", deploy_branch: "main", server_id: servers(:one).id }
      }

      app = AppRecord.find_by!(name: "native-born-app")
      expect(app.wokkud_native).to be true
      expect(app.wokkud_routed).to be true
      expect(app.wokkud_git).to be true
      expect(app.wokkud_lifecycle).to be true
    end

    it "creates the app's DNS record via the configured dns_provider" do
      post "/dashboard/apps", params: {
        app_record: { name: "dns-born-app", deploy_branch: "main", server_id: servers(:one).id }
      }
      expect(Wokku.config.dns_provider).to have_received(:create_app_record).with("dns-born-app", servers(:one).host)
    end
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
end
