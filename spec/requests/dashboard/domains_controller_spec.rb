# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Domains", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }
  let(:app_record) { app_records(:two) }
  let(:domain) { domains(:two) }

  # W6: domain writes are control-plane-only — any host SSH is a regression.
  before do
    allow(Hosts::Ssh).to receive(:new).and_raise("W6: domain flows must not SSH")
  end

  describe "auth guard" do
    it "redirects to login when not authenticated on index" do
      get "/dashboard/apps/#{app_record.id}/domains"
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET index" do
    it "renders the domains index when authenticated" do
      sign_in user
      get "/dashboard/apps/#{app_record.id}/domains"
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST create" do
    it "creates a domain and redirects" do
      sign_in user
      expect {
        post "/dashboard/apps/#{app_record.id}/domains",
             params: { domain: { hostname: "new.example.com" } }
      }.to change { app_record.domains.count }.by(1)
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/domains")
    end
  end

  describe "POST ssl" do
    it "enables ssl for a domain and redirects" do
      sign_in user
      post "/dashboard/apps/#{app_record.id}/domains/#{domain.id}/ssl"
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/domains")
    end
  end

  describe "DELETE destroy" do
    it "destroys a domain and redirects" do
      sign_in user
      expect {
        delete "/dashboard/apps/#{app_record.id}/domains/#{domain.id}"
      }.to change { app_record.domains.count }.by(-1)
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/domains")
    end
  end
end
