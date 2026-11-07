require "rails_helper"

RSpec.describe Preview::Deployer do
  let(:server) { create(:server) }
  let(:team) { create(:team) }
  let(:user) { create(:user, github_installation_id: 42) }
  let!(:membership) { create(:team_membership, team: team, user: user, role: :admin) }
  let(:parent) do
    create(:app_record, team: team, server: server, name: "myapp",
           github_repo_full_name: "octo/repo", preview_enabled: true,
           database_strategy: "empty")
  end
  let(:event) do
    Preview::PrEvent.new(provider: :github, action: :opened, pr_number: 7,
                         branch: "feat/x", sha: "abc1234",
                         repo_full_name: "octo/repo", title: "Add feat",
                         installation_id: 42, author: "octocat")
  end
  let(:dns) { instance_double(Preview::DnsRegistrar, register: true) }
  let(:commenter) { instance_double(Preview::Commenter, deployed!: true) }
  let(:bare_repo) { instance_double(Git::BareRepo, ensure!: nil, path: "/tmp/preview.git") }

  before do
    allow(Preview::DnsRegistrar).to receive(:new).and_return(dns)
    allow(Preview::Commenter).to receive(:new).and_return(commenter)
    # Native build path — stub the git fetch/archive and the shared
    # build+converge service so the spec exercises the deployer's
    # orchestration, not real git/registry I/O.
    allow(Git::BareRepo).to receive(:new).and_return(bare_repo)
    allow(GithubDeployJob).to receive(:system_fetch).and_return(true)
    allow(Git::PushDeployer).to receive(:archive_and_upload).and_return("deploy-archives/x/y.tar.gz")
    allow(Deploys::BuildAndConverge).to receive(:call).and_return("build log\n")
    allow_any_instance_of(described_class).to receive(:resolve_sha).and_return("a" * 40)
  end

  it "fetches a private repo with the GitHub App installation token" do
    allow(GithubApp).to receive(:configured?).and_return(true)
    allow(GithubApp).to receive(:new).with(42).and_return(instance_double(GithubApp, access_token: "ghs_tok"))
    described_class.new(parent: parent, event: event).call
    expect(GithubDeployJob).to have_received(:system_fetch)
      .with(bare_repo, "https://github.com/octo/repo.git", "feat/x", token: "ghs_tok")
  end

  it "creates the preview natively and never calls dokku" do
    expect(Hosts::Ssh).not_to receive(:new)

    preview = described_class.new(parent: parent, event: event).call

    expect(preview.wokkud_native).to be true
    expect(preview.wokkud_routed).to be true
    expect(preview.wokkud_git).to be true
    expect(preview.wokkud_lifecycle).to be true
    expect(preview.billing_exempt).to be true
  end

  it "creates a preview AppRecord on first deploy with billing_exempt=true" do
    expect { described_class.new(parent: parent, event: event).call }
      .to change { parent.reload.preview_apps.count }.by(1)

    preview = parent.preview_apps.first
    expect(preview.is_preview).to be(true)
    expect(preview.billing_exempt).to be(true)
    expect(preview.pr_number).to eq(7)
    expect(preview.deploy_branch).to eq("feat/x")
    expect(preview.last_commit_sha).to eq("abc1234")
    expect(preview.last_commit_at).to be_present
  end

  it "builds through the shared native service, marks the deploy succeeded, and comments on the PR" do
    described_class.new(parent: parent, event: event).call

    preview = parent.reload.preview_apps.first
    deploy = preview.deploys.first
    expect(Deploys::BuildAndConverge).to have_received(:call).with(app: preview, deploy: deploy)
    expect(deploy.commit_sha).to eq("abc1234")
    expect(deploy.archive_key).to eq("deploy-archives/x/y.tar.gz")
    expect(deploy.status).to eq("succeeded")
    expect(preview.status).to eq("running")
    expect(commenter).to have_received(:deployed!)
  end

  it "is idempotent — re-running with the same SHA does not rebuild" do
    described_class.new(parent: parent, event: event).call
    expect(Deploys::BuildAndConverge).to receive(:call).exactly(0).times
    described_class.new(parent: parent, event: event).call
  end

  it "redeploys when SHA changes" do
    described_class.new(parent: parent, event: event).call
    new_event = Preview::PrEvent.new(provider: :github, action: :synchronize, pr_number: 7,
                                     branch: "feat/x", sha: "def4567",
                                     repo_full_name: "octo/repo", title: "x",
                                     installation_id: 42, author: "u")
    described_class.new(parent: parent, event: new_event).call
    expect(parent.reload.preview_apps.first.last_commit_sha).to eq("def4567")
  end

  it "marks the deploy failed and the preview crashed when the build raises" do
    allow(Deploys::BuildAndConverge).to receive(:call)
      .and_raise(Deploys::BuildAndConverge::Error, "wokkud build failed")

    expect { described_class.new(parent: parent, event: event).call }.not_to raise_error

    preview = parent.reload.preview_apps.first
    deploy = preview.deploys.first
    expect(deploy.status).to eq("failed")
    expect(deploy.log).to include("wokkud build failed")
    expect(preview.status).to eq("crashed")
  end

  it "fails the deploy cleanly when the preview name exceeds the git-repo length cap" do
    parent.update!(name: "a" * 60) # "<60>-pr-7" > 63 chars
    long_event = Preview::PrEvent.new(provider: :github, action: :opened, pr_number: 7,
                                      branch: "feat/x", sha: "abc1234",
                                      repo_full_name: "octo/repo", title: "t",
                                      installation_id: 42, author: "u")

    expect { described_class.new(parent: parent, event: long_event).call }.not_to raise_error

    preview = parent.reload.preview_apps.first
    expect(preview.deploys.first.status).to eq("failed")
    expect(preview.status).to eq("crashed")
  end

  it "fails the deploy cleanly when the github fetch raises (network error, auth failure, private/nonexistent repo)" do
    allow(GithubDeployJob).to receive(:system_fetch).and_raise(RuntimeError, "Command failed with exit 128")

    expect { described_class.new(parent: parent, event: event).call }.not_to raise_error

    preview = parent.reload.preview_apps.first
    deploy = preview.deploys.first
    expect(deploy.status).to eq("failed")
    expect(deploy.log).to include("Command failed with exit 128")
    expect(preview.status).to eq("crashed")
    expect(commenter).not_to have_received(:deployed!)
  end

  it "fails the deploy cleanly when archive_and_upload raises Git::PushDeployer::Error" do
    allow(Git::PushDeployer).to receive(:archive_and_upload)
      .and_raise(Git::PushDeployer::Error.new(:archive_failed, "could not archive abc1234 — retry the push"))

    expect { described_class.new(parent: parent, event: event).call }.not_to raise_error

    preview = parent.reload.preview_apps.first
    deploy = preview.deploys.first
    expect(deploy.status).to eq("failed")
    expect(deploy.log).to include("could not archive abc1234")
    expect(preview.status).to eq("crashed")
    expect(commenter).not_to have_received(:deployed!)
  end

  it "removes a stale parent DATABASE_URL from an existing preview" do
    dsn = "postgres://postgres:pw@dokku.postgres.proddb:5432/proddb"
    db = create(:database_service, name: "proddb", server: server, dsn: dsn)
    create(:app_database, app_record: parent, database_service: db)
    parent.env_vars.create!(key: "DATABASE_URL", value: dsn, scope: "both")
    preview = described_class.new(parent: parent, event: event).call
    Apps::EnvWriter.set(preview, "DATABASE_URL" => dsn) # as an older deploy left it
    preview.deploys.destroy_all

    described_class.new(parent: parent, event: event).call

    expect(preview.reload.runtime_env).not_to have_key("DATABASE_URL")
  end
end
