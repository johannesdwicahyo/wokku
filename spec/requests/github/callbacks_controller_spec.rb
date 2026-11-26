# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Github::CallbacksController", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }
  let(:json) { { "Content-Type" => "application/json" } }

  before do
    sign_in user
    allow(GithubApp).to receive(:configured?).and_return(true)
    allow(GithubApp).to receive(:jwt).and_return("app-jwt")
  end

  def stub_installation(id, updated_at: 2.minutes.ago, login: "octocat")
    stub_request(:get, "https://api.github.com/app/installations/#{id}")
      .with(headers: { "Authorization" => "Bearer app-jwt" })
      .to_return(status: 200, headers: json,
                 body: { id: id, account: { login: login },
                         created_at: 1.year.ago.iso8601, updated_at: updated_at.iso8601 }.to_json)
  end

  def expect_refused
    expect(response).to redirect_to(dashboard_apps_path)
    expect(flash[:alert]).to eq(I18n.t("dashboard.github.install_refused"))
  end

  it "redirects to sign in when unauthenticated" do
    sign_out user
    get github_callback_path, params: { installation_id: "12345" }
    expect(response).to be_redirect
  end

  it "saves a freshly created/updated installation with the account login" do
    stub_installation(42)
    get github_callback_path, params: { installation_id: "42" }
    expect(response).to redirect_to(dashboard_apps_path)
    expect(flash[:notice]).to eq(I18n.t("dashboard.github.install_connected"))
    expect(user.reload.github_installation_id).to eq(42)
    expect(user.github_username).to eq("octocat")
  end

  it "refuses an installation not touched in the last 15 minutes (guessed id)" do
    stub_installation(42, updated_at: 20.minutes.ago)
    expect { get github_callback_path, params: { installation_id: "42" } }
      .not_to(change { user.reload.attributes })
    expect_refused
  end

  it "refuses an installation id another Wokku user holds" do
    create(:user, github_installation_id: 42)
    stub_installation(42)
    get github_callback_path, params: { installation_id: "42" }
    expect_refused
    expect(user.reload.github_installation_id).not_to eq(42)
  end

  it "lets the current user re-save their own installation" do
    user.update!(github_installation_id: 42)
    stub_installation(42)
    get github_callback_path, params: { installation_id: "42" }
    expect(flash[:notice]).to eq(I18n.t("dashboard.github.install_connected"))
  end

  it "refuses missing, non-numeric, zero and negative ids" do
    [ nil, "abc", "0", "-5", "42abc" ].each do |bad|
      get github_callback_path, params: { installation_id: bad }.compact
      expect_refused
    end
    expect(user.reload.github_installation_id).to be_nil
  end

  it "refuses when GitHub errors (unknown installation)" do
    stub_request(:get, "https://api.github.com/app/installations/42").to_return(status: 404)
    get github_callback_path, params: { installation_id: "42" }
    expect_refused
    expect(user.reload.github_installation_id).to be_nil
  end

  it "refuses when the GitHub App isn't configured" do
    allow(GithubApp).to receive(:configured?).and_return(false)
    get github_callback_path, params: { installation_id: "42" }
    expect_refused
  end

  context "with a user-authorization code and OAuth configured" do
    before do
      stub_const("GithubApp::CLIENT_ID", "cid")
      stub_const("GithubApp::CLIENT_SECRET", "csecret")
      stub_request(:post, "https://github.com/login/oauth/access_token")
        .to_return(status: 200, headers: json, body: { access_token: "user-token" }.to_json)
    end

    def stub_user_installations(*ids)
      stub_request(:get, %r{\Ahttps://api.github.com/user/installations})
        .with(headers: { "Authorization" => "token user-token" })
        .to_return(status: 200, headers: json,
                   body: { total_count: ids.size, installations: ids.map { |i| { id: i } } }.to_json)
    end

    it "saves an installation the user can access, even if it is old" do
      stub_installation(42, updated_at: 1.year.ago)
      stub_user_installations(7, 42)
      get github_callback_path, params: { installation_id: "42", code: "abc" }
      expect(user.reload.github_installation_id).to eq(42)
      expect(user.github_username).to eq("octocat")
    end

    it "requires the code once OAuth is configured (no 15-minute fallback)" do
      stub_installation(42)
      get github_callback_path, params: { installation_id: "42" }
      expect_refused
      expect(user.reload.github_installation_id).to be_nil
    end

    it "refuses when the user-installations response has no installations" do
      stub_installation(42)
      stub_request(:get, %r{\Ahttps://api.github.com/user/installations})
        .to_return(status: 200, headers: json, body: { message: "odd" }.to_json)
      get github_callback_path, params: { installation_id: "42", code: "abc" }
      expect_refused
    end

    it "follows pagination past the first 100 installations" do
      stub_installation(42)
      page2 = "https://api.github.com/user/installations?page=2&per_page=100"
      stub_request(:get, "https://api.github.com/user/installations?per_page=100")
        .to_return(status: 200, headers: json.merge("Link" => %(<#{page2}>; rel="next")),
                   body: { total_count: 2, installations: [ { id: 7 } ] }.to_json)
      stub_request(:get, page2)
        .to_return(status: 200, headers: json, body: { total_count: 2, installations: [ { id: 42 } ] }.to_json)
      get github_callback_path, params: { installation_id: "42", code: "abc" }
      expect(user.reload.github_installation_id).to eq(42)
    end

    it "refuses an installation the user can't access, even if it is fresh" do
      stub_installation(42)
      stub_user_installations(7)
      get github_callback_path, params: { installation_id: "42", code: "abc" }
      expect_refused
      expect(user.reload.github_installation_id).to be_nil
    end
  end
end
