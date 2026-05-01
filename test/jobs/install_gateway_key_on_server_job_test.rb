require "test_helper"

class InstallGatewayKeyOnServerJobTest < ActiveJob::TestCase
  setup do
    @server = servers(:one)
    @orig_pubkey = ENV["WOKKU_GATEWAY_SSH_PUBLIC_KEY"]
  end

  teardown do
    ENV["WOKKU_GATEWAY_SSH_PUBLIC_KEY"] = @orig_pubkey
  end

  test "no-ops when WOKKU_GATEWAY_SSH_PUBLIC_KEY is unset" do
    ENV.delete("WOKKU_GATEWAY_SSH_PUBLIC_KEY")
    Dokku::SshKeys.any_instance.expects(:add).never
    InstallGatewayKeyOnServerJob.perform_now(@server.id)
  end

  test "installs an overridden name+pubkey when passed explicitly (rotation staging)" do
    ENV["WOKKU_GATEWAY_SSH_PUBLIC_KEY"] = "ssh-ed25519 AAAAOLD wokku-gateway"
    Dokku::SshKeys.any_instance.expects(:add).with("wokku-gateway-next", "ssh-ed25519 AAAANEW wokku-gateway").once
    InstallGatewayKeyOnServerJob.perform_now(@server.id, "wokku-gateway-next", "ssh-ed25519 AAAANEW wokku-gateway")
  end

  test "installs the wokku-gateway key via Dokku::SshKeys#add when configured" do
    ENV["WOKKU_GATEWAY_SSH_PUBLIC_KEY"] = "ssh-ed25519 AAAAGATEWAY wokku-gateway"
    Dokku::SshKeys.any_instance.expects(:add).with("wokku-gateway", "ssh-ed25519 AAAAGATEWAY wokku-gateway").once
    InstallGatewayKeyOnServerJob.perform_now(@server.id)
  end

  test "short-circuits when the server id is gone" do
    ENV["WOKKU_GATEWAY_SSH_PUBLIC_KEY"] = "ssh-ed25519 AAAAGATEWAY wokku-gateway"
    Dokku::SshKeys.any_instance.expects(:add).never
    InstallGatewayKeyOnServerJob.perform_now(-1)
  end

  test "swallows Dokku connection errors (logs + reports to Sentry instead)" do
    ENV["WOKKU_GATEWAY_SSH_PUBLIC_KEY"] = "ssh-ed25519 AAAAGATEWAY wokku-gateway"
    Dokku::SshKeys.any_instance.stubs(:add).raises(Dokku::Client::ConnectionError, "ssh down")
    assert_nothing_raised { InstallGatewayKeyOnServerJob.perform_now(@server.id) }
  end
end
