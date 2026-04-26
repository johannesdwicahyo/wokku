require "test_helper"

class RemoveGatewayKeyFromServerJobTest < ActiveJob::TestCase
  setup do
    @server = servers(:one)
  end

  test "removes the named key via Dokku::SshKeys#remove" do
    Dokku::SshKeys.any_instance.expects(:remove).with("wokku-gateway-old").once
    RemoveGatewayKeyFromServerJob.perform_now(@server.id, "wokku-gateway-old")
  end

  test "short-circuits when the server id is gone" do
    Dokku::SshKeys.any_instance.expects(:remove).never
    RemoveGatewayKeyFromServerJob.perform_now(-1, "wokku-gateway-old")
  end

  test "swallows Dokku connection errors (logs + reports to Sentry instead)" do
    Dokku::SshKeys.any_instance.stubs(:remove).raises(Dokku::Client::ConnectionError, "ssh down")
    assert_nothing_raised { RemoveGatewayKeyFromServerJob.perform_now(@server.id, "wokku-gateway-old") }
  end
end
