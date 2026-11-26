# frozen_string_literal: true

require "rails_helper"

# Phase 5 final fix wave: create/new behaviours found by the final review and sweep.
RSpec.describe "New app fix wave", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:user) { users(:one) }
  let(:server) { servers(:one) }
  let(:doc) { Capybara.string(response.body) }
  let(:blank_row) { { kind: "", engine: "", cpu: "", memory_mb: "", disk_gb: "", database_service_id: "" } }
  let(:web) { { cpu: "1.0", memory_mb: "1024", count: "1", sleeping: "0" } }

  before do
    sign_in user
    allow(Wokku.config).to receive(:resource_builder?).and_return(true)
    allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(true)
  end

  def post_app(name, extra = {})
    post "/dashboard/apps", params: { app_record: { name: name, server_id: server.id }, processes: { web: web }, source: "git" }.merge(extra)
  end

  RSpec::Matchers.define_negated_matcher :not_have_enqueued_job, :have_enqueued_job

  def web_alloc(app) = app.dyno_allocations.find_by(process_type: "web")

  describe "size_preset (no JS)" do
    it "sleeping wins over the posted slider values" do
      post_app("presetsleep", size_preset: "sleeping")
      expect(web_alloc(AppRecord.find_by!(name: "presetsleep")).sleeping?).to be(true)
    end

    it "a named preset wins over the sliders and turns sleeping off" do
      post_app("presetnano", size_preset: "nano", processes: { web: web.merge(sleeping: "1") })
      shape = web_alloc(AppRecord.find_by!(name: "presetnano")).shape
      expect([ shape.cpu, shape.memory_mb ]).to eq([ 0.25, 256 ])
    end

    it "custom keeps the builder fields" do
      post_app("presetcustom", size_preset: "custom")
      expect(web_alloc(AppRecord.find_by!(name: "presetcustom")).shape.memory_mb).to eq(1024)
    end
  end

  describe "shared add-ons" do
    it "enqueue one AttachAddonsJob with only the shared items and never provision inline" do
      expect(Addons::SharedProvisioner).not_to receive(:new)
      expect {
        post_app("sharedjob", addons: [ blank_row.merge(kind: "shared", engine: "postgres"),
                                        blank_row.merge(kind: "dedicated", engine: "postgres", cpu: "0.25", memory_mb: "512", disk_gb: "5") ])
      }.to have_enqueued_job(AttachAddonsJob).once.and have_enqueued_job(CreateAddonJob).once
      job = enqueued_jobs.find { |j| j["job_class"] == "AttachAddonsJob" }
      expect(job["arguments"][2].map { |i| i["kind"] }).to eq(%w[shared])
      expect(flash[:notice]).to include("Shared add-ons are being attached")
    end

    it "defers the first GitHub deploy to the job" do
      user.update!(github_installation_id: 7)
      allow(GithubApp).to receive(:repo_owned_by_installation?).and_return(true)
      expect(GithubRepos).not_to receive(:start_deploy)
      expect {
        post_app("sharedgh", source: "github", github_repo: "me/repo", github_branch: "main",
                             addons: [ blank_row.merge(kind: "shared", engine: "postgres") ])
      }.to have_enqueued_job(AttachAddonsJob).with(anything, user.id, anything, { "repo" => "me/repo", "branch" => "main" })
      expect(response).to redirect_to(dashboard_app_path(AppRecord.find_by!(name: "sharedgh")))
    end
  end

  describe "server_id" do
    it "422s with a localized error (not 404) on a blank or unknown server" do
      [ "", SecureRandom.uuid ].each do |sid|
        post "/dashboard/apps", params: { app_record: { name: "noserver", server_id: sid }, processes: { web: web } }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Choose a server.")
      end
      expect(AppRecord.find_by(name: "noserver")).to be_nil
    end

  end

  describe "GET check_name" do
    def check(name) = (get "/dashboard/apps/check_name", params: { name: name }; JSON.parse(response.body))

    it "is invalid when sanitizing would change the typed name" do
      expect(check("My_App")).to include("available" => false, "reason" => "invalid")
      expect(check("app-")).to include("available" => false, "reason" => "invalid")
    end

    it "flags reserved names" do
      expect(check("git")).to include("available" => false, "reason" => "reserved")
    end

    it "accepts a clean free name" do
      expect(check("fresh-name")).to include("available" => true)
    end
  end

  describe "messages" do
    it "names the DB, not the UUID, for a failed existing add-on" do
      other = DatabaseService.create!(name: "foreign-db", service_type: "postgres", server: server, status: :running, creator: users(:admin))
      post_app("msgexisting", addons: [ blank_row.merge(kind: "existing", engine: "postgres", database_service_id: other.id) ])
      expect(flash[:warning]).to include("foreign-db")
      expect(flash[:warning]).not_to include(other.id.to_s)
    end

    it "says the repo could not be verified for the installation on an ownership refusal" do
      user.update!(github_installation_id: 7)
      allow(GithubApp).to receive(:repo_owned_by_installation?).and_return(false)
      post_app("msgverify", source: "github", github_repo: "victim/private")
      expect(response.body).to include("couldn&#39;t verify that repository")
      expect(response.body).not_to include("Choose a GitHub repository")
    end

    it "does not claim the repo is connected when connect was refused" do
      user.update!(github_installation_id: 7)
      allow(GithubApp).to receive(:repo_owned_by_installation?).and_return(true, false)
      post_app("msgnoconnect", source: "github", github_repo: "me/repo", github_branch: "main")
      expect(flash[:warning]).to include("couldn't connect the repository")
      expect(flash[:warning]).not_to include("is connected")
    end

    it "has no Billing page in the engine account-limit copy" do
      expect(I18n.t("new_app.errors.account_limit")).not_to match(/billing/i)
    end

    it "localizes attach errors and shape errors under :id" do
      I18n.with_locale(:id) do
        expect(I18n.t("new_app.attach.failed")).to eq("Add-on tidak bisa dipasang")
        expect(Resources::Shape.new(cpu: 9, memory_mb: 256).errors.first).to match(/harus/)
      end
      expect(Resources::Shape.new(cpu: 9, memory_mb: 256).errors.first).to eq("CPU must be 0.25–4.0 in steps of 0.25")
    end
  end

  describe "first_deploy_started" do
    it "fires on the GitHub path too" do
      AppRecord.where(id: user.app_records.select(:id)).destroy_all
      user.update!(github_installation_id: 7)
      allow(GithubApp).to receive(:repo_owned_by_installation?).and_return(true)
      allow(GithubRepos).to receive(:head_sha).and_return("a" * 40)
      post_app("firstgh", source: "github", github_repo: "me/repo", github_branch: "main")
      expect(flash[:posthog_event]).to eq("first_deploy_started")
    end
  end

  describe "GET new" do
    it "server-renders the GitHub repos so the select works without JS" do
      user.update!(github_installation_id: 7)
      allow(GithubApp).to receive(:configured?).and_return(true)
      allow(GithubRepos).to receive(:list).with(7).and_return([ Struct.new(:full_name).new("me/repo") ])
      get "/dashboard/apps/new"
      expect(doc).to have_css("select#github_repo option[value='me/repo']", visible: :all)
    end

    it "shows the repos error note when GitHub fails, without a stale URL hint" do
      user.update!(github_installation_id: 7)
      allow(GithubApp).to receive(:configured?).and_return(true)
      allow(GithubRepos).to receive(:list).and_raise(Octokit::Error)
      get "/dashboard/apps/new"
      expect(doc).to have_text("Reload the page to try again")
      expect(doc).to have_no_text("public repo URL.")
    end

    it "shows no Price label for unpriced add-ons (self-host)" do
      Wokku.config.pricing = Wokku::Providers::NullPricing.new
      get "/dashboard/apps/new"
      expect(doc).to have_no_css("[data-new-app-target=configPrice]", visible: :all)
    end

    it "sliders and the default selected card agree (Sleeping shows the Nano shape)" do
      allow_any_instance_of(Dashboard::AppsController).to receive(:box_picker_state)
        .and_return({ "sleeping" => { remaining: 1, provisionable: true } })
      get "/dashboard/apps/new"
      expect(doc).to have_css("input[name=size_preset][value=sleeping][checked]", visible: :all)
      expect(doc).to have_css("input[name='processes[web][cpu]'][value='0.25']", visible: :all)
      expect(doc).to have_css("input[name='processes[web][memory_mb]'][value='256']", visible: :all)
    end

    it "uses the live accent on slider thumbs" do
      get "/dashboard/apps/new"
      expect(doc).to have_css("input[type=range].accent-live", minimum: 2, visible: :all)
    end

    it "localizes the existing-list status and the Dedicated label under :id" do
      db = DatabaseService.create!(name: "mia-pg", service_type: "postgres", server: server, status: :running, creator: user)
      get "/dashboard/apps/new", params: { locale: :id, server_id: server.id }
      expect(doc).to have_text("Berjalan")
      expect(response.body).not_to include("postgres · running")
      expect(doc).to have_no_text("Dedicated")
      db.destroy
    end
  end

  describe "422 re-render" do
    it "shows the taken status inline under the name" do
      AppRecord.create!(name: "taken-inline", team: teams(:one), server: server, creator: user)
      post_app("taken-inline")
      expect(doc).to have_css("#app_name_status", text: "Name already taken")
    end
  end

  describe "first-app chooser" do
    it "links to the new app page instead of opening a panel" do
      AppRecord.where(id: user.app_records.select(:id)).destroy_all
      get "/dashboard/apps"
      expect(doc).to have_link(href: "/dashboard/apps/new")
      expect(response.body).not_to include("click->slide-panel#open")
    end
  end

  describe "round 2" do
    before { allow(RepoUrlDeployJob).to receive(:valid_url?).and_return(true) }

    it "repo URL + shared add-ons: pending deploy exists, the job (not create) enqueues the build" do
      expect {
        post_app("urlshared", source: "repo_url", app_record: { name: "urlshared", server_id: server.id, git_repository_url: "https://example.com/r.git" },
                              addons: [ blank_row.merge(kind: "shared", engine: "postgres") ])
      }.to have_enqueued_job(AttachAddonsJob).and(not_have_enqueued_job(RepoUrlDeployJob))
      app = AppRecord.find_by!(name: "urlshared")
      expect(app.deploys.pending.count).to eq(1)
      expect(response).to redirect_to(dashboard_app_deploy_path(app, app.deploys.first))
      job = enqueued_jobs.find { |j| j["job_class"] == "AttachAddonsJob" }
      expect(job["arguments"][4]).to include("deploy_id" => app.deploys.first.id, "url" => "https://example.com/r.git")
    end

    it "repo URL without shared add-ons enqueues the build directly" do
      expect {
        post_app("urlplain", source: "repo_url", app_record: { name: "urlplain", server_id: server.id, git_repository_url: "https://example.com/r.git" })
      }.to have_enqueued_job(RepoUrlDeployJob).and(not_have_enqueued_job(AttachAddonsJob))
    end

    it "GET new rescues a Faraday timeout and shows the error note" do
      user.update!(github_installation_id: 7)
      allow(GithubApp).to receive(:configured?).and_return(true)
      allow(GithubRepos).to receive(:list).and_raise(Faraday::TimeoutError)
      get "/dashboard/apps/new"
      expect(response).to have_http_status(:ok)
      expect(doc).to have_text("Reload the page to try again")
    end

    it "the listing client has short timeouts and keeps Octokit's default headers" do
      opts = GithubApp.connection_options
      expect(opts[:request]).to include(open_timeout: 3, timeout: 5)
      expect(opts[:headers]).to be_present
    end

    it "blank branch (no JS) deploys the repo's default branch, not main" do
      user.update!(github_installation_id: 7)
      allow(GithubApp).to receive(:repo_owned_by_installation?).and_return(true)
      allow(GithubApp).to receive(:configured?).and_return(true)
      allow_any_instance_of(GithubApp).to receive(:default_branch).with("me/repo").and_return("master")
      expect(GithubRepos).to receive(:start_deploy).with(anything, "me/repo", "master", installation_id: 7)
      post_app("nojsbranch", source: "github", github_repo: "me/repo", github_branch: "")
      expect(AppRecord.find_by!(name: "nojsbranch").deploy_branch).to eq("master")
    end

    it "keeps the typed name on the server-required 422" do
      post "/dashboard/apps", params: { app_record: { name: "typed-name", server_id: "" }, processes: { web: web } }
      expect(doc).to have_css("input#app_record_name[value='typed-name']")
    end

    it "preselects the first server and Create is never server-less" do
      other = create(:server, team: user.teams.first)
      allow_any_instance_of(Dashboard::AppsController).to receive(:policy_scope).and_wrap_original do |m, s|
        s == Server ? Server.where(id: [ server.id, other.id ]).order(:id) : m.call(s)
      end
      get "/dashboard/apps/new"
      expect(doc).to have_css("select[name='app_record[server_id]'] option[selected]", count: 1)
    end

    {
      "Sleeping with Nano sliders when there is headroom" => [ { remaining: 1, provisionable: true }, "sleeping", "0.25", "256" ],
      "Basic with Basic sliders when there is none" => [ { remaining: 0, provisionable: false }, "basic", "0.5", "512" ]
    }.each do |title, (quota, card, cpu, mem)|
      it "preselects #{title}" do
        allow_any_instance_of(Dashboard::AppsController).to receive(:box_picker_state).and_return({ "sleeping" => quota })
        get "/dashboard/apps/new"
        expect(doc).to have_css("input[name=size_preset][value=#{card}][checked]", visible: :all)
        expect(doc).to have_css("input[name='processes[web][cpu]'][value='#{cpu}']", visible: :all)
        expect(doc).to have_css("input[name='processes[web][memory_mb]'][value='#{mem}']", visible: :all)
      end
    end

    it "renders the env-clash note slot with localized copy" do
      get "/dashboard/apps/new"
      expect(doc).to have_css("[data-new-app-target=envNote]", visible: :all)
      expect(response.body).to include("More than one add-on sets")
    end
  end
end
