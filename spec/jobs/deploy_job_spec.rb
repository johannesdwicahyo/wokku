# frozen_string_literal: true

require "rails_helper"

# W7 Phase 3: manual/API deploys go bare repo → PushDeployer →
# TarballDeployJob, same as git pushes. No dokku.
RSpec.describe DeployJob, type: :job do
  let(:deploy) { deploys(:one) }
  let(:app) { deploy.app_record }

  before do
    allow(DeployChannel).to receive(:broadcast_to).and_return(nil)
    deploy.update!(status: :pending, commit_sha: nil, finished_at: nil)
  end

  it "can be enqueued" do
    expect { described_class.perform_later(deploy.id) }.to have_enqueued_job(described_class)
  end

  it "returns early when deploy not found" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  it "routes through PushDeployer with the bare repo's HEAD sha" do
    allow_any_instance_of(described_class).to receive(:head_sha).and_return("deadbeefcafe")
    pusher = instance_double(Git::PushDeployer, call: deploy)
    expect(Git::PushDeployer).to receive(:new)
      .with(app, sha: "deadbeefcafe", ref: "refs/heads/main", deploy: deploy)
      .and_return(pusher)

    described_class.perform_now(deploy.id)
  end

  it "prefers an explicitly passed commit_sha over HEAD" do
    pusher = instance_double(Git::PushDeployer, call: deploy)
    expect(Git::PushDeployer).to receive(:new)
      .with(app, sha: "abc123def45", ref: "refs/heads/main", deploy: deploy)
      .and_return(pusher)

    described_class.perform_now(deploy.id, commit_sha: "abc123def45")
  end

  it "prefers the deploy row's stored commit_sha over HEAD" do
    deploy.update!(commit_sha: "def456abc78")
    pusher = instance_double(Git::PushDeployer, call: deploy)
    expect(Git::PushDeployer).to receive(:new)
      .with(app, sha: "def456abc78", ref: "refs/heads/main", deploy: deploy)
      .and_return(pusher)

    described_class.perform_now(deploy.id)
  end

  it "fails with a clear message when the app has never been pushed (no HEAD)" do
    allow_any_instance_of(described_class).to receive(:head_sha).and_return(nil)
    expect(Git::PushDeployer).not_to receive(:new)

    described_class.perform_now(deploy.id)

    expect(deploy.reload.status).to eq("failed")
    expect(deploy.log).to include("no code has been pushed")
    expect(deploy.finished_at).to be_present
    expect(app.reload.status).to eq("created")
    expect(DeployChannel).to have_received(:broadcast_to)
      .with(deploy, { type: "status", data: "failed" })
  end

  it "marks the deploy failed when PushDeployer raises" do
    allow_any_instance_of(described_class).to receive(:head_sha).and_return("deadbeefcafe")
    allow(Git::PushDeployer).to receive(:new)
      .and_raise(Git::PushDeployer::Error.new(:archive_failed, "could not archive deadbee — retry the push"))

    described_class.perform_now(deploy.id)

    expect(deploy.reload.status).to eq("failed")
    expect(deploy.log).to include("could not archive")
    expect(app.reload.status).to eq("created")
    expect(DeployChannel).to have_received(:broadcast_to)
      .with(deploy, { type: "status", data: "failed" })
  end
end
