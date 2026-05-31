# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubDeployJob, type: :job do
  let(:app) { app_records(:one) }
  let(:deploy) { deploys(:one) }

  let(:base_args) do
    {
      app_id: app.id, deploy_id: deploy.id,
      repo_full_name: "owner/repo", branch: "main", commit_sha: "abc123"
    }
  end

  before do
    allow(DeployChannel).to receive(:broadcast_to).and_return(nil)
  end

  def stub_streaming(&block)
    allow_any_instance_of(Dokku::Client).to receive(:run_streaming) { |_, _cmd, &b| block.call(b) }
  end

  it "can be enqueued" do
    expect { described_class.perform_later(**base_args) }.to have_enqueued_job(described_class)
  end

  it "marks deploy as succeeded on successful run" do
    stub_streaming { |b| b.call("git sync output\n") }
    described_class.perform_now(**base_args.merge(commit_sha: "abc1234567890"))
    expect(deploy.reload.status).to eq("succeeded")
    expect(app.reload.status).to eq("running")
    expect(deploy.reload.commit_sha).to eq("abc1234567890")
  end

  it "marks deploy as failed on CommandError" do
    allow_any_instance_of(Dokku::Client).to receive(:run_streaming).and_raise(Dokku::Client::CommandError, "git sync failed")
    described_class.perform_now(**base_args)
    expect(deploy.reload.status).to eq("failed")
    expect(app.reload.status).to eq("crashed")
    expect(deploy.reload.log).to include("git sync failed")
  end

  it "marks deploy as timed_out on Timeout::Error" do
    allow_any_instance_of(Dokku::Client).to receive(:run_streaming).and_raise(Timeout::Error, "deploy timed out")
    described_class.perform_now(**base_args)
    expect(deploy.reload.status).to eq("timed_out")
    expect(app.reload.status).to eq("crashed")
    expect(deploy.reload.log).to include("timed out")
  end

  it "transitions app to running after success" do
    app.update!(status: :running)
    stub_streaming { |b| b.call("building\n") }
    described_class.perform_now(**base_args)
    expect(app.reload.status).to eq("running")
  end

  it "streams deploy log output" do
    stub_streaming do |b|
      b.call("chunk one\n")
      b.call("chunk two\n")
    end
    described_class.perform_now(**base_args)
    log = deploy.reload.log
    expect(log).to include("chunk one")
    expect(log).to include("chunk two")
  end
end
