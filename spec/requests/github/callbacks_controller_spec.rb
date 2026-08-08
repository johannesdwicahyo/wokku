# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Github::CallbacksController", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }

  before { sign_in user }

  it "redirects to sign in when unauthenticated" do
    sign_out user
    get github_callback_path, params: { installation_id: "12345" }
    expect(response).to be_redirect
  end

  it "stores installation id when provided" do
    allow(GithubApp).to receive(:configured?).and_return(false)
    get github_callback_path, params: { installation_id: "99999" }
    expect(response).to redirect_to(dashboard_apps_path)
    expect(user.reload.github_installation_id.to_i).to eq(99999)
  end

  it "persists fetched github username when GithubApp is configured" do
    owner = OpenStruct.new(login: "octocat")
    repo = OpenStruct.new(owner: owner)
    repos = OpenStruct.new(repositories: [ repo ])
    allow(GithubApp).to receive(:configured?).and_return(true)
    allow_any_instance_of(GithubApp).to receive(:repos).and_return(repos)

    get github_callback_path, params: { installation_id: "42" }
    expect(user.reload.github_username).to eq("octocat")
  end

  it "swallows GithubApp errors and still persists installation_id" do
    allow(GithubApp).to receive(:configured?).and_return(true)
    allow_any_instance_of(GithubApp).to receive(:repos).and_raise(StandardError, "api down")

    get github_callback_path, params: { installation_id: "42" }
    expect(user.reload.github_installation_id.to_i).to eq(42)
    expect(user.github_username).to be_nil
  end

  it "shows alert when installation_id is missing" do
    get github_callback_path
    expect(response).to redirect_to(dashboard_apps_path)
    expect(flash[:alert]).to match(/failed/i)
  end
end
