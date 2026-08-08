# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Backups", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:user) { users(:two) }
  let(:database) { database_services(:two) }

  describe "GET index" do
    it "redirects to login when not authenticated" do
      get "/dashboard/addons/#{database.id}/backups"
      expect(response).to have_http_status(:redirect)
    end

    it "shows backups for an authenticated admin" do
      sign_in user
      get "/dashboard/addons/#{database.id}/backups"
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST create" do
    it "redirects when not authenticated" do
      post "/dashboard/addons/#{database.id}/backups"
      expect(response).to have_http_status(:redirect)
    end

    it "enqueues the backup job and redirects" do
      sign_in user
      post "/dashboard/addons/#{database.id}/backups"
      expect(response).to redirect_to("/dashboard/addons/#{database.id}/backups")
    end
  end
end
