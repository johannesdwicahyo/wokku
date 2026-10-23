# frozen_string_literal: true

require "rails_helper"

RSpec.describe BitbucketDeployJob, type: :job do
  let(:app) { create(:app_record, wokkud_git: true) }
  let(:deploy) { create(:deploy, app_record: app, status: :pending) }

  let(:enqueue_args) do
    {
      app_id: app.id, deploy_id: deploy.id,
      repo_full_name: "o/r", branch: "main", commit_sha: "abc123"
    }
  end

  before do
    allow(DeployChannel).to receive(:broadcast_to).and_return(nil)
  end

  it "fetches into the bare repo and reuses the deploy via PushDeployer" do
    deployer = instance_double(Git::PushDeployer, call: deploy)
    fake_repo = instance_double(Git::BareRepo, ensure!: nil, path: "/tmp/x.git")
    allow(Git::BareRepo).to receive(:new).with(app.name).and_return(fake_repo)
    expect(described_class).to receive(:system_fetch).with(fake_repo, "https://bitbucket.org/o/r.git", "main")
    expect(Git::PushDeployer).to receive(:new)
      .with(app, sha: "abc123", ref: "refs/heads/main", deploy: deploy).and_return(deployer)
    described_class.perform_now(**enqueue_args)
  end

  it "never touches Dokku::Client — deploys are wokkud-only" do
    allow(Git::BareRepo).to receive(:new).and_return(instance_double(Git::BareRepo, ensure!: nil, path: "/tmp/x.git"))
    allow(described_class).to receive(:system_fetch)
    allow(Git::PushDeployer).to receive(:new).and_return(instance_double(Git::PushDeployer, call: deploy))
    expect(Hosts::Ssh).not_to receive(:new)
    described_class.perform_now(**enqueue_args)
  end

  it "marks the pre-created deploy as failed (not left pending) when PushDeployer raises" do
    allow(Git::BareRepo).to receive(:new).and_return(instance_double(Git::BareRepo, ensure!: nil, path: "/tmp/x.git"))
    allow(described_class).to receive(:system_fetch)
    allow(Git::PushDeployer).to receive(:new)
      .and_raise(Git::PushDeployer::Error.new(:archive_failed, "could not archive abc123 — retry the push"))

    described_class.perform_now(**enqueue_args)

    expect(deploy.reload.status).to eq("failed")
    expect(app.reload.status).to eq("created")
    expect(deploy.reload.log).to include("could not archive")
  end

  it "marks the pre-created deploy as failed (not stuck pending forever) when bare repo init raises" do
    allow_any_instance_of(Git::BareRepo).to receive(:ensure!).and_raise(Errno::EACCES, "/var/lib/wokku/git")

    described_class.perform_now(**enqueue_args)

    expect(deploy.reload.status).to eq("failed")
    expect(app.reload.status).to eq("created")
  end
end
