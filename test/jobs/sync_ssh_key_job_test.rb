require "test_helper"

class SyncSshKeyJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @key = @user.ssh_public_keys.create!(name: "primary", public_key: "ssh-ed25519 AAAAfake", fingerprint: "SHA256:k1")
    @team = teams(:one)
    @server = servers(:one)
    @app = app_records(:one)
  end

  test "add syncs key + ACLs to all team servers" do
    Dokku::SshKeys.any_instance.expects(:add).with(
      "wokku-user-#{@user.id}-key-#{@key.id}", @key.public_key
    ).once
    Dokku::Acl.any_instance.expects(:grant_team_apps).once
    SyncSshKeyJob.perform_now(@key.id, @user.id, action: :add)
  end

  test "remove revokes ACLs and deletes key from all team servers" do
    Dokku::Acl.any_instance.expects(:revoke_all).once
    Dokku::SshKeys.any_instance.expects(:remove).with(
      "wokku-user-#{@user.id}-key-#{@key.id}"
    ).once
    SyncSshKeyJob.perform_now(@key.id, @user.id, action: :remove)
  end

  test "add is a no-op when the key id cannot be found" do
    Dokku::SshKeys.any_instance.expects(:add).never
    SyncSshKeyJob.perform_now(-1, @user.id, action: :add)
  end

  test "returns early when user not found" do
    Dokku::SshKeys.any_instance.expects(:add).never
    SyncSshKeyJob.perform_now(@key.id, -1, action: :add)
  end

  test "returns early when user has no team" do
    lonely = User.create!(email: "lonely@example.com", password: "password123456")
    lonely_key = lonely.ssh_public_keys.create!(name: "x", public_key: "ssh-rsa AA", fingerprint: "SHA256:zzz")
    Dokku::SshKeys.any_instance.expects(:add).never
    SyncSshKeyJob.perform_now(lonely_key.id, lonely.id, action: :add)
  end

  test "continues to next server when one raises" do
    Dokku::SshKeys.any_instance.stubs(:add).raises(StandardError, "boom")
    assert_nothing_raised { SyncSshKeyJob.perform_now(@key.id, @user.id, action: :add) }
  end
end
