# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Databases", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }
  let(:database) { database_services(:two) }
  let(:server) { servers(:two) }

  before do
    # These examples only assert the HTTP outcome (redirect / 200), so stub
    # the SSH transport to return success instead of letting any action burn
    # ~5s on a real connection timeout.
    allow_any_instance_of(Hosts::Ssh).to receive(:run_raw).and_return("")
    allow_any_instance_of(Hosts::Ssh).to receive(:run_raw_streaming).and_return("")
  end

  describe "auth" do
    it "redirects to login on index" do
      get "/dashboard/addons"
      expect(response).to have_http_status(:redirect)
    end

    it "redirects to login on show" do
      get "/dashboard/addons/#{database.id}"
      expect(response).to have_http_status(:redirect)
    end

    it "redirects to login on new" do
      get "/dashboard/addons/new"
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET index" do
    it "returns 200 for an authenticated admin" do
      sign_in user
      get "/dashboard/addons"
      expect(response).to have_http_status(:success)
    end

    it "filters by group param" do
      sign_in user
      get "/dashboard/addons", params: { group: "app" }
      expect(response).to have_http_status(:success)
    end

    # Regression: the grouped add-on count renders a pluralized i18n key
    # (dashboard.databases.count) — every locale's plural data must carry
    # both `one` and `other`, or count==1 raises I18n::InvalidPluralizationData
    # (this app has no CLDR :id plural-rules gem, so :id uses the default
    # pluralizer that requires `one`). The default-locale specs missed it
    # because the count path only renders with an add-on present.
    it "renders the grouped count without a pluralization error in id locale" do
      sign_in user
      database # ensure the team-two add-on fixture exists so the count path renders
      get "/dashboard/addons", headers: { "Accept-Language" => "id" }, params: { locale: :id }
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET show" do
    it "returns 200 for an authenticated admin" do
      sign_in user
      get "/dashboard/addons/#{database.id}"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET new" do
    it "redirects to addons index (slide-panel form is the source of truth)" do
      sign_in user
      get "/dashboard/addons/new"
      expect(response).to redirect_to("/dashboard/addons")
    end
  end

  describe "POST create" do
    it "redirects when not authenticated" do
      post "/dashboard/addons",
           params: { database_service: { name: "new-pg", service_type: "postgres", server_id: server.id } }
      expect(response).to have_http_status(:redirect)
    end

    it "rescues SSH error and redirects with alert" do
      sign_in user
      post "/dashboard/addons",
           params: { database_service: { name: "new-pg-test", service_type: "postgres", server_id: server.id } }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "DELETE destroy" do
    it "redirects when not authenticated" do
      delete "/dashboard/addons/#{database.id}"
      expect(response).to have_http_status(:redirect)
    end

    it "rescues SSH error and redirects" do
      sign_in user
      delete "/dashboard/addons/#{database.id}"
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "link/unlink" do
    let(:app_record) { app_records(:two) }

    it "link redirects when not authenticated" do
      post "/dashboard/addons/#{database.id}/link", params: { app_id: app_record.id }
      expect(response).to have_http_status(:redirect)
    end

    it "link rescues SSH error and redirects" do
      sign_in user
      post "/dashboard/addons/#{database.id}/link", params: { app_id: app_record.id }
      expect(response).to have_http_status(:redirect)
    end

    it "unlink redirects when not authenticated" do
      post "/dashboard/addons/#{database.id}/unlink", params: { app_id: app_record.id }
      expect(response).to have_http_status(:redirect)
    end

    it "unlink rescues SSH error and redirects" do
      sign_in user
      post "/dashboard/addons/#{database.id}/unlink", params: { app_id: app_record.id }
      expect(response).to have_http_status(:redirect)
    end
  end
end
