# frozen_string_literal: true

require "rails_helper"

RSpec.describe GrantAppAclJob, type: :job do
  let(:app) { app_records(:one) }
  let(:user) { users(:one) }

  before do
    user.ssh_public_keys.create!(name: "primary", public_key: "ssh-ed25519 AAAAfake user@host", fingerprint: "SHA256:aaa")
    user.ssh_public_keys.create!(name: "laptop", public_key: "ssh-ed25519 AAAAbob user@laptop", fingerprint: "SHA256:bbb")
  end

  it "adds ACL entry for each of user's ssh keys" do
    expect_any_instance_of(Dokku::Acl).to receive(:add).twice.and_return(nil)
    described_class.perform_now(app.id, user.id)
  end

  it "key name format is stable and includes user+key ids" do
    seen_names = []
    allow_any_instance_of(Dokku::Acl).to receive(:add) do |_, _app_name, key_name|
      seen_names << key_name
    end
    described_class.perform_now(app.id, user.id)
    user.ssh_public_keys.each do |key|
      expect(seen_names).to include("wokku-user-#{user.id}-key-#{key.id}")
    end
  end

  it "continues processing remaining keys after per-key CommandError" do
    first_key = user.ssh_public_keys.first
    allow_any_instance_of(Dokku::Acl).to receive(:add) do |_, app_name, key_name|
      if app_name == app.name && key_name == "wokku-user-#{user.id}-key-#{first_key.id}"
        raise Dokku::Client::CommandError.new("boom")
      end
      nil
    end
    expect { described_class.perform_now(app.id, user.id) }.not_to raise_error
  end

  it "returns early when app not found" do
    expect_any_instance_of(Dokku::Acl).not_to receive(:add)
    described_class.perform_now(-1, user.id)
  end

  it "returns early when user not found" do
    expect_any_instance_of(Dokku::Acl).not_to receive(:add)
    described_class.perform_now(app.id, -1)
  end

  it "swallows top-level exceptions so job doesn't fail" do
    allow_any_instance_of(Dokku::Client).to receive(:run).and_raise(Net::SSH::AuthenticationFailed, "auth")
    expect { described_class.perform_now(app.id, user.id) }.not_to raise_error
  end
end
