# frozen_string_literal: true

require "rails_helper"

RSpec.describe GitlabDeployJob, type: :job do
  let(:app) { app_records(:one) }
  let(:deploy) { deploys(:one) }

  before do
    allow_any_instance_of(Dokku::Client).to receive(:run_streaming) { |_, _cmd, &b| b.call("ok\n") }
    allow(DeployChannel).to receive(:broadcast_to).and_return(nil)
  end

  let(:enqueue_args) do
    {
      app_id: app.id, deploy_id: deploy.id,
      repo_full_name: "group/repo", branch: "main", commit_sha: "abc1234567"
    }
  end

  it "marks deploy as succeeded on happy path" do
    described_class.perform_now(**enqueue_args)
    expect(deploy.reload.status).to eq("succeeded")
    expect(app.reload.status).to eq("running")
  end

  it "enqueues PostDeploySetupJob after success" do
    expect { described_class.perform_now(**enqueue_args) }
      .to have_enqueued_job(PostDeploySetupJob).with(app.id)
  end

  it "marks deploy failed on Dokku CommandError" do
    allow_any_instance_of(Dokku::Client).to receive(:run_streaming).and_raise(Dokku::Client::CommandError.new("build failed"))
    described_class.perform_now(**enqueue_args)
    expect(deploy.reload.status).to eq("failed")
  end

  it "marks deploy timed_out on Timeout::Error" do
    allow_any_instance_of(Dokku::Client).to receive(:run_streaming).and_raise(Timeout::Error, "slow")
    described_class.perform_now(**enqueue_args)
    expect(deploy.reload.status).to eq("timed_out")
    expect(app.reload.status).to eq("crashed")
  end
end
