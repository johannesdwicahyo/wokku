# frozen_string_literal: true

require "rails_helper"

RSpec.describe InstallGatewayKeyOnServerJob, type: :job do
  let(:server) { servers(:one) }

  around do |ex|
    orig = ENV["WOKKU_GATEWAY_SSH_PUBLIC_KEY"]
    ex.run
    ENV["WOKKU_GATEWAY_SSH_PUBLIC_KEY"] = orig
  end

  it "no-ops when WOKKU_GATEWAY_SSH_PUBLIC_KEY is unset" do
    ENV.delete("WOKKU_GATEWAY_SSH_PUBLIC_KEY")
    expect_any_instance_of(Dokku::SshKeys).not_to receive(:add)
    described_class.perform_now(server.id)
  end

  it "installs an overridden name+pubkey when passed explicitly (rotation staging)" do
    ENV["WOKKU_GATEWAY_SSH_PUBLIC_KEY"] = "ssh-ed25519 AAAAOLD wokku-gateway"
    expect_any_instance_of(Dokku::SshKeys).to receive(:add).with("wokku-gateway-next", "ssh-ed25519 AAAANEW wokku-gateway").once
    described_class.perform_now(server.id, "wokku-gateway-next", "ssh-ed25519 AAAANEW wokku-gateway")
  end

  it "installs the wokku-gateway key via Dokku::SshKeys#add when configured" do
    ENV["WOKKU_GATEWAY_SSH_PUBLIC_KEY"] = "ssh-ed25519 AAAAGATEWAY wokku-gateway"
    expect_any_instance_of(Dokku::SshKeys).to receive(:add).with("wokku-gateway", "ssh-ed25519 AAAAGATEWAY wokku-gateway").once
    described_class.perform_now(server.id)
  end

  it "short-circuits when the server id is gone" do
    ENV["WOKKU_GATEWAY_SSH_PUBLIC_KEY"] = "ssh-ed25519 AAAAGATEWAY wokku-gateway"
    expect_any_instance_of(Dokku::SshKeys).not_to receive(:add)
    described_class.perform_now(-1)
  end

  it "swallows Dokku connection errors (logs + reports to Sentry instead)" do
    ENV["WOKKU_GATEWAY_SSH_PUBLIC_KEY"] = "ssh-ed25519 AAAAGATEWAY wokku-gateway"
    allow_any_instance_of(Dokku::SshKeys).to receive(:add).and_raise(Dokku::Client::ConnectionError, "ssh down")
    expect { described_class.perform_now(server.id) }.not_to raise_error
  end
end
