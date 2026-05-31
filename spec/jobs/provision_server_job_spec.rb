# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProvisionServerJob, type: :job do
  let(:server) { servers(:one) }
  let!(:credential) do
    c = CloudCredential.new(provider: "hetzner", name: "test-cred", team: teams(:one))
    c.save(validate: false)
    c
  end

  def build_mock_ssh(exec_calls: nil)
    mock_channel = Object.new
    mock_channel.define_singleton_method(:wait) { true }

    mock_ch = Object.new
    mock_ch.define_singleton_method(:on_data) { |&_b| }
    mock_ch.define_singleton_method(:on_extended_data) { |&_b| }
    mock_ch.define_singleton_method(:exec) { |_cmd, &b| b.call(mock_ch, true) }

    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:exec!) { |cmd| exec_calls << cmd if exec_calls; "" }
    mock_ssh.define_singleton_method(:open_channel) { |&b| b.call(mock_ch); mock_channel }
    mock_ssh
  end

  def stub_hetzner(status:)
    fake_provider = Object.new
    fake_provider.define_singleton_method(:server_status) { |_id| status }
    allow(CloudProviders::Hetzner).to receive(:new).and_return(fake_provider)
    fake_provider
  end

  it "can be enqueued" do
    expect {
      described_class.perform_later(
        server_id: server.id,
        cloud_credential_id: credential.id,
        cloud_server_id: "srv-123"
      )
    }.to have_enqueued_job(described_class)
  end

  it "sets server to connected on successful provision" do
    stub_hetzner(status: "running")
    mock_ssh = build_mock_ssh
    allow(Net::SSH).to receive(:start) { |*_args, **_opts, &block| block.call(mock_ssh) }
    allow_any_instance_of(described_class).to receive(:sleep)

    described_class.perform_now(
      server_id: server.id,
      cloud_credential_id: credential.id,
      cloud_server_id: "srv-123"
    )

    expect(server.reload.status).to eq("connected")
  end

  it "sets server to unreachable on provider API failure" do
    fake_provider = Object.new
    fake_provider.define_singleton_method(:server_status) { |_id| raise "API error" }
    allow(CloudProviders::Hetzner).to receive(:new).and_return(fake_provider)

    described_class.perform_now(
      server_id: server.id,
      cloud_credential_id: credential.id,
      cloud_server_id: "srv-123"
    )

    expect(server.reload.status).to eq("unreachable")
  end

  it "sets server to unreachable on SSH failure" do
    stub_hetzner(status: "running")
    allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed, "auth failed")
    allow_any_instance_of(described_class).to receive(:sleep)

    described_class.perform_now(
      server_id: server.id,
      cloud_credential_id: credential.id,
      cloud_server_id: "srv-123"
    )

    expect(server.reload.status).to eq("unreachable")
  end

  it "installs dokku plugins via SSH exec!" do
    stub_hetzner(status: "running")
    exec_calls = []
    mock_ssh = build_mock_ssh(exec_calls: exec_calls)
    allow(Net::SSH).to receive(:start) { |*_args, **_opts, &block| block.call(mock_ssh) }
    allow_any_instance_of(described_class).to receive(:sleep)

    described_class.perform_now(
      server_id: server.id,
      cloud_credential_id: credential.id,
      cloud_server_id: "srv-123"
    )

    expect(exec_calls.any? { |c| c.include?("dokku-postgres") }).to be true
    expect(exec_calls.any? { |c| c.include?("dokku-redis") }).to be true
    expect(exec_calls.any? { |c| c.include?("letsencrypt") }).to be true
  end

  it "marks server unreachable when it does not start within MAX_WAIT" do
    stub_hetzner(status: "pending") # never becomes running
    allow_any_instance_of(described_class).to receive(:sleep)

    described_class.perform_now(
      server_id: server.id,
      cloud_credential_id: credential.id,
      cloud_server_id: "srv-123"
    )

    expect(server.reload.status).to eq("unreachable")
  end
end
