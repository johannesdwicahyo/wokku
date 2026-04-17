require "test_helper"

class GrantAppAclJobTest < ActiveJob::TestCase
  setup do
    @app = app_records(:one)
    @user = users(:one)
    @user.ssh_public_keys.create!(name: "primary", public_key: "ssh-ed25519 AAAAfake user@host", fingerprint: "SHA256:aaa")
    @user.ssh_public_keys.create!(name: "laptop", public_key: "ssh-ed25519 AAAAbob user@laptop", fingerprint: "SHA256:bbb")
  end

  test "adds ACL entry for each of user's ssh keys" do
    Dokku::Acl.any_instance.expects(:add).twice.returns(nil)
    GrantAppAclJob.perform_now(@app.id, @user.id)
  end

  test "key name format is stable and includes user+key ids" do
    seen_names = []
    Dokku::Acl.any_instance.stubs(:add).with do |_app_name, key_name|
      seen_names << key_name
      true
    end.returns(nil)
    GrantAppAclJob.perform_now(@app.id, @user.id)
    @user.ssh_public_keys.each do |key|
      assert_includes seen_names, "wokku-user-#{@user.id}-key-#{key.id}"
    end
  end

  test "continues processing remaining keys after per-key CommandError" do
    first_key = @user.ssh_public_keys.first
    Dokku::Acl.any_instance.stubs(:add)
      .with(@app.name, "wokku-user-#{@user.id}-key-#{first_key.id}")
      .raises(Dokku::Client::CommandError.new("boom"))
    Dokku::Acl.any_instance.stubs(:add).returns(nil)
    assert_nothing_raised { GrantAppAclJob.perform_now(@app.id, @user.id) }
  end

  test "returns early when app not found" do
    Dokku::Acl.any_instance.expects(:add).never
    GrantAppAclJob.perform_now(-1, @user.id)
  end

  test "returns early when user not found" do
    Dokku::Acl.any_instance.expects(:add).never
    GrantAppAclJob.perform_now(@app.id, -1)
  end

  test "swallows top-level exceptions so job doesn't fail" do
    Dokku::Client.any_instance.stubs(:run).raises(Net::SSH::AuthenticationFailed, "auth")
    assert_nothing_raised { GrantAppAclJob.perform_now(@app.id, @user.id) }
  end
end
