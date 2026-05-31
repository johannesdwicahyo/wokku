# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Checks", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }
  let(:app_record) { app_records(:two) }

  # Stand-in for Dokku::Checks so we don't actually SSH.
  class FakeDokkuChecks
    def report(*) = { "checks_disabled" => "false", "checks_wait" => "5" }
    def enable(*); end
    def disable(*); end
    def set(*); end
  end

  before do
    allow(Dokku::Client).to receive(:new).and_return(Object.new)
    allow(Dokku::Checks).to receive(:new).and_return(FakeDokkuChecks.new)
  end

  describe "auth guard" do
    it "redirects to login when not authenticated on show" do
      get "/dashboard/apps/#{app_record.id}/checks"
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET show" do
    it "renders the checks page when authenticated" do
      sign_in user
      get "/dashboard/apps/#{app_record.id}/checks"
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH update" do
    it "updates checks settings and redirects with notice" do
      sign_in user
      patch "/dashboard/apps/#{app_record.id}/checks",
            params: { checks_enabled: "1", check_path: "/health", checks_wait: "3", checks_timeout: "10", checks_attempts: "5" }
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/checks")
      expect(flash[:notice]).to match("saved")
    end

    it "disables checks and redirects with notice" do
      sign_in user
      patch "/dashboard/apps/#{app_record.id}/checks",
            params: { checks_enabled: "0" }
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/checks")
      expect(flash[:notice]).to match("saved")
    end

    it "redirects with alert when Dokku raises" do
      sign_in user
      bad_checks = Object.new
      bad_checks.define_singleton_method(:enable) { |*| raise RuntimeError, "SSH error" }
      bad_checks.define_singleton_method(:disable) { |*| raise RuntimeError, "SSH error" }
      bad_checks.define_singleton_method(:set) { |*| }
      allow(Dokku::Checks).to receive(:new).and_return(bad_checks)

      patch "/dashboard/apps/#{app_record.id}/checks", params: { checks_enabled: "1" }
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/checks")
      expect(flash[:alert]).to match("Failed")
    end
  end
end
