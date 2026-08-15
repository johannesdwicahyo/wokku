# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Logs", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:two) }
  let(:app_record) { app_records(:two) }

  it "redirects to login when not authenticated" do
    get "/dashboard/apps/#{app_record.id}/logs"
    expect(response).to have_http_status(:redirect)
  end

  it "shows logs page when authenticated (logs may be nil due to no SSH)" do
    sign_in user
    get "/dashboard/apps/#{app_record.id}/logs"
    expect(response).to have_http_status(:success)
  end

  describe "glance, time parsing and live-fetch fallbacks" do
    before { sign_in user }

    it "renders the 5-line glance partial" do
      allow(Apps::LogReader).to receive(:recent).and_return("\e[32mok\e[0m line-a\nline-b")
      get "/dashboard/apps/#{app_record.id}/logs", params: { glance: 1 }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("line-a")
      expect(response.body).not_to include("\e[32m")
    end

    it "glance swallows a log-reader failure and renders empty" do
      allow(Apps::LogReader).to receive(:recent).and_raise(IOError, "ssh down")
      get "/dashboard/apps/#{app_record.id}/logs", params: { glance: 1 }
      expect(response).to have_http_status(:success)
    end

    it "parses ISO8601 since/until and falls back for loose formats" do
      get "/dashboard/apps/#{app_record.id}/logs",
          params: { since: 2.hours.ago.iso8601, until: "not a !!! time" }
      expect(response).to have_http_status(:success)
    end

    it "deferred live fetch degrades to nil when the reader raises" do
      allow(Apps::LogReader).to receive(:recent).and_raise(IOError, "host gone")
      get "/dashboard/apps/#{app_record.id}/logs",
          params: { deferred: 1, source: "live" }
      expect(response).to have_http_status(:success)
    end
  end
end
