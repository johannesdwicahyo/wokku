# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubDeployJob, type: :job do
  let(:app) { create(:app_record, wokkud_git: true) }
  let(:deploy) { create(:deploy, app_record: app, status: :pending) }

  let(:base_args) do
    {
      app_id: app.id, deploy_id: deploy.id,
      repo_full_name: "o/r", branch: "main", commit_sha: "abc123"
    }
  end

  before do
    allow(DeployChannel).to receive(:broadcast_to).and_return(nil)
  end

  it "can be enqueued" do
    expect { described_class.perform_later(**base_args) }.to have_enqueued_job(described_class)
  end

  it "fetches into the bare repo and reuses the deploy via PushDeployer" do
    deployer = instance_double(Git::PushDeployer, call: deploy)
    fake_repo = instance_double(Git::BareRepo, ensure!: nil, path: "/tmp/x.git")
    allow(Git::BareRepo).to receive(:new).with(app.name).and_return(fake_repo)
    expect(described_class).to receive(:system_fetch).with(fake_repo, "https://github.com/o/r.git", "main", token: nil)
    expect(Git::PushDeployer).to receive(:new)
      .with(app, sha: "abc123", ref: "refs/heads/main", deploy: deploy).and_return(deployer)
    described_class.perform_now(**base_args)
  end

  it "fetches a private repo with the GitHub App installation token, passed via env (not argv)" do
    fake_repo = instance_double(Git::BareRepo, ensure!: nil, path: "/tmp/x.git")
    allow(Git::BareRepo).to receive(:new).and_return(fake_repo)
    allow(Git::PushDeployer).to receive(:new).and_return(instance_double(Git::PushDeployer, call: deploy))
    allow(GithubApp).to receive(:configured?).and_return(true)
    allow(GithubApp).to receive(:new).with(42).and_return(instance_double(GithubApp, access_token: "inst-tok"))
    calls = []
    allow(described_class).to receive(:system) { |*args, **kw| calls << [ args, kw ]; true }

    described_class.perform_now(**base_args, installation_id: 42)

    (env, *argv), _kw = calls.first
    expect(argv).not_to include(a_string_including("inst-tok"))
    expect(env["GIT_CONFIG_KEY_0"]).to eq("http.https://github.com/.extraheader")
    expect(Base64.decode64(env["GIT_CONFIG_VALUE_0"].delete_prefix("Authorization: Basic "))).to eq("x-access-token:inst-tok")
  end

  it "never touches Dokku::Client — deploys are wokkud-only" do
    allow(Git::BareRepo).to receive(:new).and_return(instance_double(Git::BareRepo, ensure!: nil, path: "/tmp/x.git"))
    allow(described_class).to receive(:system_fetch)
    allow(Git::PushDeployer).to receive(:new).and_return(instance_double(Git::PushDeployer, call: deploy))
    expect(Hosts::Ssh).not_to receive(:new)
    described_class.perform_now(**base_args)
  end

  it "marks the pre-created deploy as failed (not left pending) when PushDeployer raises" do
    allow(Git::BareRepo).to receive(:new).and_return(instance_double(Git::BareRepo, ensure!: nil, path: "/tmp/x.git"))
    allow(described_class).to receive(:system_fetch)
    allow(Git::PushDeployer).to receive(:new)
      .and_raise(Git::PushDeployer::Error.new(:archive_failed, "could not archive abc123 — retry the push"))

    described_class.perform_now(**base_args)

    expect(deploy.reload.status).to eq("failed")
    expect(app.reload.status).to eq("created")
    expect(deploy.reload.log).to include("could not archive")
  end

  it "marks the pre-created deploy as failed (not stuck pending forever) when bare repo init raises" do
    allow_any_instance_of(Git::BareRepo).to receive(:ensure!).and_raise(Errno::EACCES, "/var/lib/wokku/git")

    described_class.perform_now(**base_args)

    expect(deploy.reload.status).to eq("failed")
    expect(app.reload.status).to eq("created")
  end
end
