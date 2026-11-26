# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /dashboard/apps (Phase 5 create flow)", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:user) { users(:one) }
  let(:server) { servers(:one) }
  let(:preset) { { processes: { web: { cpu: "0.5", memory_mb: "512", count: "1", sleeping: "0" } }, size_preset: "basic" } }
  let(:blank_row) { { kind: "", engine: "", cpu: "", memory_mb: "", disk_gb: "", database_service_id: "" } }

  before do
    sign_in user
    allow(Wokku.config).to receive(:resource_builder?).and_return(true)
    allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(true)
  end

  def post_app(name, extra = {})
    post "/dashboard/apps", params: { app_record: { name: name, server_id: server.id } }.merge(preset).merge(extra)
  end

  it "plain POST with source=git and no add-ons creates the app and lands on the overview" do
    post_app("flowgit", source: "git")
    app = AppRecord.find_by!(name: "flowgit")
    expect(response).to redirect_to(dashboard_app_path(app))
  end

  it "attaches a shared and a dedicated add-on in the same submit" do
    expect {
      post_app("flowaddons", addons: [
        blank_row.merge(kind: "shared", engine: "postgres"),
        blank_row.merge(kind: "dedicated", engine: "postgres", cpu: "0.25", memory_mb: "512", disk_gb: "5")
      ])
    }.to have_enqueued_job(CreateAddonJob).once
    expect(AppRecord.find_by!(name: "flowaddons").app_databases.count).to eq(2)
  end

  it "keeps the app and warns when an existing add-on is not attachable" do
    other = DatabaseService.create!(name: "foreign-db", service_type: "postgres", server: server, status: :running, creator: users(:admin))
    post_app("flowexisting", addons: [ blank_row.merge(kind: "existing", database_service_id: other.id) ])
    app = AppRecord.find_by!(name: "flowexisting")
    expect(app.app_databases.count).to eq(0)
    expect(flash[:warning]).to include("add-ons could not be attached")
  end

  it "connects the repo and enqueues the first deploy for source=github" do
    user.update!(github_installation_id: 7)
    allow(GithubApp).to receive(:repo_owned_by_installation?).and_return(true)
    allow(GithubRepos).to receive(:head_sha).with(7, "me/repo", "main").and_return("a" * 40)
    expect {
      post_app("flowgh", source: "github", github_repo: "me/repo", github_branch: "main",
                         app_record: { name: "flowgh", server_id: server.id, git_repository_url: "https://example.com/ignored" })
    }.to have_enqueued_job(GithubDeployJob)
    app = AppRecord.find_by!(name: "flowgh")
    expect(app.github_repo_full_name).to eq("me/repo")
    expect(response).to redirect_to(dashboard_app_deploy_path(app, app.deploys.first))
  end

  it "refuses a repo owned by another installation: 422, nothing connected" do
    user.update!(github_installation_id: 7)
    allow(GithubApp).to receive(:repo_owned_by_installation?).with("victim/private", 7).and_return(false)
    post_app("flowvictim", source: "github", github_repo: "victim/private", github_branch: "main")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(AppRecord.find_by(name: "flowvictim")).to be_nil
  end

  it "keeps the app and warns (no 500) when GitHub is misconfigured after save" do
    user.update!(github_installation_id: 7)
    allow(GithubApp).to receive(:repo_owned_by_installation?).and_return(true)
    allow(GithubApp).to receive(:configured?).and_return(false)
    post_app("flowmisconf", source: "github", github_repo: "me/repo", github_branch: "main")
    expect(AppRecord.find_by!(name: "flowmisconf")).to be_present
    expect(response).to redirect_to(dashboard_app_path(AppRecord.find_by!(name: "flowmisconf")))
    expect(flash[:warning]).to be_present
  end

  it "rescues JWT/key errors in head_sha" do
    allow(GithubApp).to receive(:configured?).and_return(true)
    allow(GithubApp).to receive(:new).and_raise(OpenSSL::PKey::PKeyError)
    expect(GithubRepos.head_sha(7, "me/repo", "main")).to be_nil
  end

  it "skips the first deploy with a warning when the server is disconnected" do
    user.update!(github_installation_id: 7)
    allow(GithubApp).to receive(:repo_owned_by_installation?).and_return(true)
    allow_any_instance_of(Server).to receive(:connected?).and_return(false)
    expect { post_app("flowdisc", source: "github", github_repo: "me/repo", github_branch: "main") }
      .not_to have_enqueued_job(GithubDeployJob)
    expect(flash[:warning]).to be_present
  end

  it "does not 500 on a non-hash addons param" do
    post_app("flowjunk", source: "git", addons: "x")
    expect(response).to redirect_to(dashboard_app_path(AppRecord.find_by!(name: "flowjunk")))
  end

  it "ignores hidden github fields when source=git" do
    user.update!(github_installation_id: 7)
    post_app("flowhidden", source: "git", github_repo: "me/repo")
    expect(AppRecord.find_by!(name: "flowhidden").github_repo_full_name).to be_nil
  end

  it "re-renders new with 422 keeping preset, source and add-on rows on a taken name" do
    AppRecord.create!(name: "taken-name", team: teams(:one), server: server, creator: user)
    post "/dashboard/apps", params: { app_record: { name: "taken-name", server_id: server.id },
                                       source: "git",
                                       processes: { web: { cpu: "1.0", memory_mb: "1024", count: "1", sleeping: "0" } },
                                       addons: [ blank_row.merge(kind: "shared", engine: "postgres") ] }
    expect(response).to have_http_status(:unprocessable_entity)
    doc = Capybara.string(response.body)
    expect(doc).to have_css("form[data-controller~='new-app']")
    expect(doc).to have_text(/taken/i)
    expect(doc).to have_css("input[name=size_preset][value=standard][checked]", visible: :all)
    expect(doc).to have_css("input[name=source][value=git][checked]", visible: :all)
    expect(doc).to have_css("input[name='addons[][engine]'][value=postgres]", visible: :all)
  end

  it "still redirects to billing on a deposit shortfall" do
    enforcer = Wokku.config.plan_enforcer
    allow(enforcer).to receive(:deposit_shortfall).and_return({ balance: 0, required: 1 })
    # The billing route lives in the cloud app, not the engine.
    without_partial_double_verification do
      allow_any_instance_of(Dashboard::AppsController).to receive(:dashboard_billing_path).and_return("/dashboard/billing")
    end
    post_app("flowbroke", source: "git")
    expect(response).to redirect_to("/dashboard/billing")
    expect(AppRecord.find_by(name: "flowbroke")).to be_nil
  end
end
