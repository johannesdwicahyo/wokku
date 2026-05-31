# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Github", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }
  let(:app_record) { app_records(:two) }

  it "redirects to login when not authenticated on repos" do
    get "/dashboard/apps/#{app_record.id}/github/repos"
    expect(response).to have_http_status(:redirect)
  end

  it "repos redirects when no github installation_id" do
    sign_in user
    user.update!(github_installation_id: nil)
    get "/dashboard/apps/#{app_record.id}/github/repos"
    expect(response).to have_http_status(:redirect)
  end

  it "redirects to login when not authenticated on connect" do
    post "/dashboard/apps/#{app_record.id}/github/connect", params: { repo: "owner/repo", branch: "main" }
    expect(response).to have_http_status(:redirect)
  end

  it "connect updates app and redirects when authenticated" do
    sign_in user
    post "/dashboard/apps/#{app_record.id}/github/connect", params: { repo: "owner/repo", branch: "main" }
    expect(response).to have_http_status(:redirect)
    expect(app_record.reload.github_repo_full_name).to eq("owner/repo")
  end

  it "redirects to login when not authenticated on disconnect" do
    delete "/dashboard/apps/#{app_record.id}/github/disconnect"
    expect(response).to have_http_status(:redirect)
  end

  it "disconnect clears repo and redirects when authenticated" do
    sign_in user
    app_record.update!(github_repo_full_name: "owner/repo")
    delete "/dashboard/apps/#{app_record.id}/github/disconnect"
    expect(response).to have_http_status(:redirect)
    expect(app_record.reload.github_repo_full_name).to be_nil
  end
end
