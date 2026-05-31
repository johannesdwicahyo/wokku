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
                         branch: "feat/x", sha: "abc123",
                         repo_full_name: "octo/repo", title: "Add feat",
                         installation_id: 42, author: "octocat")
  end
  let(:client) { instance_double(Dokku::Client) }
  let(:apps_svc) { instance_double(Dokku::Apps) }
  let(:config_svc) { instance_double(Dokku::Config, set: true) }
  let(:dns) { instance_double(Preview::DnsRegistrar, register: true) }
  let(:db_provisioner) { instance_double(Preview::DatabaseProvisioner::Empty, provision: true) }
  let(:commenter) { instance_double(Preview::Commenter, deployed!: true) }

  before do
    allow(Dokku::Client).to receive(:new).with(server).and_return(client)
    allow(Dokku::Apps).to receive(:new).with(client).and_return(apps_svc)
    allow(Dokku::Config).to receive(:new).with(client).and_return(config_svc)
    allow(Preview::DnsRegistrar).to receive(:new).and_return(dns)
    allow(Preview::DatabaseProvisioner::Empty).to receive(:new).and_return(db_provisioner)
    allow(Preview::Commenter).to receive(:new).and_return(commenter)
    allow(apps_svc).to receive(:create)
    allow(client).to receive(:run_streaming).and_yield("ok\n")
  end

  it "creates a preview AppRecord on first deploy with billing_exempt=true" do
    expect(apps_svc).to receive(:create).with("myapp-pr-7")

    expect { described_class.new(parent: parent, event: event).call }
      .to change { parent.reload.preview_apps.count }.by(1)

    preview = parent.preview_apps.first
    expect(preview.is_preview).to be(true)
    expect(preview.billing_exempt).to be(true)
    expect(preview.pr_number).to eq(7)
    expect(preview.deploy_branch).to eq("feat/x")
    expect(preview.last_commit_sha).to eq("abc123")
    expect(preview.last_commit_at).to be_present
  end

  it "creates a Deploy record + streams build log + marks deploy succeeded" do
    described_class.new(parent: parent, event: event).call
    preview = parent.reload.preview_apps.first
    deploy = preview.deploys.first
    expect(deploy.commit_sha).to eq("abc123")
    expect(deploy.status).to eq("succeeded")
    expect(preview.status).to eq("running")
  end

  it "is idempotent — re-running with the same SHA does not redeploy" do
    described_class.new(parent: parent, event: event).call
    expect(apps_svc).not_to receive(:create)
    expect(client).not_to receive(:run_streaming)
    described_class.new(parent: parent, event: event).call
  end

  it "redeploys when SHA changes" do
    described_class.new(parent: parent, event: event).call
    new_event = Preview::PrEvent.new(provider: :github, action: :synchronize, pr_number: 7,
                                     branch: "feat/x", sha: "def456",
                                     repo_full_name: "octo/repo", title: "x",
                                     installation_id: 42, author: "u")
    expect(client).to receive(:run_streaming).at_least(:once).and_yield("ok\n")
    described_class.new(parent: parent, event: new_event).call
    expect(parent.reload.preview_apps.first.last_commit_sha).to eq("def456")
  end

  it "marks deploy failed on Dokku::Client::CommandError and does not crash" do
    allow(client).to receive(:run_streaming).and_raise(Dokku::Client::CommandError, "git sync failed")
    expect { described_class.new(parent: parent, event: event).call }.not_to raise_error
    preview = parent.reload.preview_apps.first
    deploy = preview.deploys.first
    expect(deploy.status).to eq("failed")
    expect(preview.status).to eq("crashed")
  end
end
