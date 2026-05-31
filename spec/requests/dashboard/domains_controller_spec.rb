# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Domains", type: :request do
  include Devise::Test::IntegrationHelpers

  # Null object for Dokku::Domains — absorbs any call.
  class FakeDokkuDomains
    def add(*); end
    def remove(*); end
    def enable_ssl(*); end
  end

  let(:user) { users(:two) }
  let(:app_record) { app_records(:two) }
  let(:domain) { domains(:two) }

  before do
    allow(Dokku::Client).to receive(:new).and_return(Object.new)
    allow(Dokku::Domains).to receive(:new).and_return(FakeDokkuDomains.new)
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
