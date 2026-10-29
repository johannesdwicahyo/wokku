# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Terminals", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:admin) }
  let(:app_record) { app_records(:two) }
  let(:server)     { servers(:two) }

  it "redirects to login when not authenticated on app terminal" do
    get "/dashboard/apps/#{app_record.id}/terminal"
    expect(response).to have_http_status(:redirect)
  end

  it "shows the app console to an admin of the app's team" do
    sign_in users(:two)
    get "/dashboard/apps/#{app_record.id}/terminal"
    expect(response).to have_http_status(:success)
  end

  it "keeps outsiders and team viewers out of the app console" do
    outsider = User.create!(email: "outsider-console@example.com", password: "password123456")
    viewer = User.create!(email: "viewer-console@example.com", password: "password123456")
    TeamMembership.create!(user: viewer, team: app_record.team, role: :viewer)

    [ outsider, viewer ].each do |u|
      sign_in u
      get "/dashboard/apps/#{app_record.id}/terminal"
      expect(response).to redirect_to("/dashboard/apps")
      sign_out u
    end
  end

  it "redirects to login when not authenticated on server terminal" do
    get "/admin/servers/#{server.id}/terminal"
    expect(response).to have_http_status(:redirect)
  end

  it "shows server terminal when authenticated as admin" do
    sign_in user
    get "/admin/servers/#{server.id}/terminal"
    expect(response).to have_http_status(:success)
  end

  it "redirects non-team-member away from server terminal" do
    outsider = User.create!(email: "outsider@example.com", password: "password123456")
    sign_in outsider
    server_one = servers(:one)
    get "/admin/servers/#{server_one.id}/terminal"
    expect([ 302, 403, 404 ]).to include(response.status)
  end
end
