# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeployJob, type: :job do
  let(:deploy) { deploys(:one) }
  let(:app) { deploy.app_record }

  before do
    allow(DeployChannel).to receive(:broadcast_to).and_return(nil)
  end

  def stub_streaming(&block)
    allow_any_instance_of(Dokku::Client).to receive(:run_streaming) { |_, _cmd, &b| block.call(b) }
  end

  it "can be enqueued" do
    expect { described_class.perform_later(deploy.id) }.to have_enqueued_job(described_class)
  end

  it "marks deploy as succeeded on successful run" do
    stub_streaming { |b| b.call("deploy output\n") }
    described_class.perform_now(deploy.id)
    expect(deploy.reload.status).to eq("succeeded")
    expect(app.reload.status).to eq("running")
  end

  it "marks deploy as failed on CommandError" do
    allow_any_instance_of(Dokku::Client).to receive(:run_streaming).and_raise(Dokku::Client::CommandError.new("command failed"))
    described_class.perform_now(deploy.id)
    expect(deploy.reload.status).to eq("failed")
    expect(app.reload.status).to eq("crashed")
  end

  it "marks deploy as timed_out on Timeout::Error" do
    allow_any_instance_of(Dokku::Client).to receive(:run_streaming).and_raise(Timeout::Error, "timed out")
    described_class.perform_now(deploy.id)
    expect(deploy.reload.status).to eq("timed_out")
    expect(app.reload.status).to eq("crashed")
    expect(deploy.reload.log).to include("timed out")
  end

  it "returns early when deploy not found" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  it "sets deploy status to building at start" do
    deploy.update!(status: :pending)
    stub_streaming { |b| b.call("building...\n") }
    described_class.perform_now(deploy.id)
    expect(deploy.reload.status).to eq("succeeded")
    expect(deploy.reload.started_at).not_to be_nil
  end

  it "appends streaming log output to deploy log" do
    stub_streaming do |b|
      b.call("line one\n")
      b.call("line two\n")
    end
    described_class.perform_now(deploy.id)
    log = deploy.reload.log
    expect(log).to include("line one")
    expect(log).to include("line two")
  end

  it "stores commit_sha when provided" do
    stub_streaming { |b| b.call("") }
    described_class.perform_now(deploy.id, commit_sha: "deadbeef1234")
    expect(deploy.reload.commit_sha).to eq("deadbeef1234")
  end
end
