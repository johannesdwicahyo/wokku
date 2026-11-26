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

  it "repos renders an install prompt in the tab when no github installation_id" do
    sign_in user
    user.update!(github_installation_id: nil)
    get "/dashboard/apps/#{app_record.id}/github/repos"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Install the GitHub App")
  end

  it "repos shows an alert instead of a 500 when GitHub is unreachable" do
    sign_in user
    user.update!(github_installation_id: 42)
    allow_any_instance_of(GithubApp).to receive(:repos).and_raise(Faraday::ConnectionFailed, "down")
    get "/dashboard/apps/#{app_record.id}/github/repos"
    expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/releases")
    expect(flash[:alert]).to be_present
  end

  it "redirects to login when not authenticated on connect" do
    post "/dashboard/apps/#{app_record.id}/github/connect", params: { repo: "owner/repo", branch: "main" }
    expect(response).to have_http_status(:redirect)
  end

  describe "connect ownership" do
    before do
      user.update!(github_installation_id: 42)
      allow(GithubApp).to receive(:configured?).and_return(true)
      allow(GithubApp).to receive(:jwt).and_return("app-jwt")
      sign_in user
    end

    def stub_installation(**response)
      stub_request(:get, "https://api.github.com/repos/owner/repo/installation")
        .to_return(**response)
    end

    it "links a repo in the user's own installation" do
      stub_installation(status: 200, headers: { "Content-Type" => "application/json" }, body: { id: 42 }.to_json)
      post "/dashboard/apps/#{app_record.id}/github/connect", params: { repo: "owner/repo", branch: "main" }
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/releases")
      expect(app_record.reload.github_repo_full_name).to eq("owner/repo")
    end

    it "refuses a repo owned by another installation" do
      stub_installation(status: 200, headers: { "Content-Type" => "application/json" }, body: { id: 99 }.to_json)
      post "/dashboard/apps/#{app_record.id}/github/connect", params: { repo: "owner/repo", branch: "main" }
      expect(response).to redirect_to("/dashboard/apps/#{app_record.id}/releases")
      expect(flash[:alert]).to eq(I18n.t("dashboard.github.repo_not_owned"))
      expect(app_record.reload.github_repo_full_name).to be_nil
    end

    it "refuses when GitHub errors" do
      stub_installation(status: 500)
      post "/dashboard/apps/#{app_record.id}/github/connect", params: { repo: "owner/repo", branch: "main" }
      expect(flash[:alert]).to eq(I18n.t("dashboard.github.repo_not_owned"))
      expect(app_record.reload.github_repo_full_name).to be_nil
    end
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

  describe "GET repo_list (New app form)" do
    let(:path) { "/dashboard/github/repo_list" }

    it "requires sign in" do
      get path
      expect(response).to have_http_status(:redirect)
    end

    it "returns empty lists without an installation" do
      sign_in user
      user.update!(github_installation_id: nil)
      get path
      expect(JSON.parse(response.body)).to eq("repos" => [], "branches" => [])
    end

    it "lists the installation's repos and a repo's branches through GithubRepos" do
      sign_in user
      user.update!(github_installation_id: 7)
      repo = Struct.new(:full_name, :default_branch).new("acme/web", "main")
      allow(GithubRepos).to receive(:list).with(7).and_return([ repo ])
      allow(GithubRepos).to receive(:branches).with(7, "acme/web").and_return(%w[main dev])
      get path
      expect(JSON.parse(response.body)["repos"]).to eq([ { "full_name" => "acme/web", "default_branch" => "main" } ])
      get path, params: { repo: "acme/web" }
      expect(JSON.parse(response.body)["branches"]).to eq(%w[main dev])
    end

    it "answers 502 when GitHub errors" do
      sign_in user
      user.update!(github_installation_id: 7)
      allow(GithubRepos).to receive(:list).and_raise(Octokit::Error)
      get path
      expect(response).to have_http_status(:bad_gateway)
    end
  end
end
