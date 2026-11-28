# frozen_string_literal: true

require "rails_helper"

# Self-host (no billing host — this harness) regressions from the
# 2026-11-16 install audit: pages that 500'd on cloud-only billing code,
# a workspace form that demanded a paid plan nobody can buy, and
# wokku.cloud-only copy shown to self-hosters.
RSpec.describe "Self-host dashboard pages", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }

  before { sign_in user }

  it "renders the profile edit page (was a 500 on resource_usages)" do
    get "/dashboard/profile/edit"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Billing currency")
  end

  it "redirects the plan/invoice usage page instead of a 500" do
    get "/dashboard/usage"
    expect(response).to redirect_to("/dashboard/apps")
  end

  it "renders an incoming app transfer without cloud price helpers (was a 500)" do
    transfer = AppTransfer.create!(app_record: app_records(:one), from_user: users(:one), to_user: users(:two))
    sign_in users(:two)
    get "/dashboard/app_transfers/#{transfer.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Estimated Monthly Cost", "Billing will start")
  end

  it "creates a workspace without a paid plan" do
    expect {
      post "/dashboard/workspaces", params: { team: { name: "Selfhost Org #{SecureRandom.hex(3)}" } }
    }.to change { user.teams.count }.by(1)
    expect(user.teams.order(:created_at).last.plan.key).to eq("free")
  end

  it "does not show paid-plan copy on the workspaces page" do
    get "/dashboard/workspaces"
    expect(response.body).not_to include("require a paid plan")
    expect(response.body).not_to match(/Rp[\d.]+\/mo/)
  end

  it "shows no wokku.cloud support inbox, billing currency, or API host" do
    get "/dashboard/profile"
    expect(response.body).not_to include("support@wokku.cloud", "Billing currency", "https://wokku.cloud/api")
    expect(response.body).to include("http://www.example.com/api/v1")
  end

  it "gives a user who signed up without a team (email sign-up) a personal team" do
    teamless = User.create!(email: "teamless-#{SecureRandom.hex(3)}@example.test", password: "a-long-password-123")
    expect(teamless.teams).to be_empty
    sign_in teamless
    get "/dashboard/apps"
    expect(response).to have_http_status(:ok)
    expect(teamless.reload.personal_team).to be_present
  end

  it "shows the running image's release, not the gem's placeholder version" do
    orig = ENV["WOKKU_VERSION"]
    ENV["WOKKU_VERSION"] = "2026.11.16-abc1234"
    get "/dashboard/apps"
    expect(response.body).to include("wokku 2026.11.16-abc1234")
  ensure
    orig ? ENV["WOKKU_VERSION"] = orig : ENV.delete("WOKKU_VERSION")
  end

  describe "deploying your own code from a public repository" do
    let(:server) { servers(:two) }

    it "creates the app, names the release, and starts the build" do
      allow(RepoUrlDeployJob).to receive(:valid_url?).and_return(true)
      expect {
        post "/dashboard/apps", params: { app_record: { name: "from-repo-#{SecureRandom.hex(2)}", server_id: server.id,
                                                        git_repository_url: "https://github.com/o/r" } }
      }.to have_enqueued_job(RepoUrlDeployJob).with(hash_including(url: "https://github.com/o/r", branch: "main"))
      app = AppRecord.order(:created_at).last
      expect(app.git_repository_url).to eq("https://github.com/o/r")
      expect(app.releases.last.description).to eq("Deploy from https://github.com/o/r")
      expect(response).to redirect_to(%r{/dashboard/apps/#{app.id}/deploys/})
    end

    it "refuses a non-public repository address without creating the app" do
      expect {
        post "/dashboard/apps", params: { app_record: { name: "bad-repo", server_id: server.id, git_repository_url: "file:///etc" } }
      }.not_to change(AppRecord, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it "sign-in has no cloud pitch and no half sentence about terms" do
    sign_out :user
    get "/users/sign_in"
    expect(response.body).not_to include("no card", "you agree to our")
    expect(response.body).to include("Your apps are waiting.")
  end

  it "settings talk about this install, not billing or git push" do
    get "/dashboard/profile"
    expect(response.body).not_to include("and billing", "billing currency can be set", "Dynos", "enable <code class=\"font-mono text-accent\">git push")
    expect(response.body).to include("Manage your account, security and API credentials.")
  end

  # No plan page on self-host: an unavailable picker card linked "upgrade
  # plan →" to "#".
  it "offers no plan-upgrade link in the database picker" do
    get "/dashboard/addons"
    expect(response.body).to include('data-addon-tier-picker-plan-upgrade-url-value=""')
  end
end
