# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncSshKeyJob, type: :job do
  let(:user) { users(:one) }
  let!(:key) do
    user.ssh_public_keys.create!(
      name: "primary",
      public_key: "ssh-ed25519 AAAAfake",
      fingerprint: "SHA256:k1"
    )
  end

  it "add syncs key + ACLs to all team servers" do
    expect_any_instance_of(Dokku::SshKeys).to receive(:add).with(
      "wokku-user-#{user.id}-key-#{key.id}", key.public_key
    ).once
    expect_any_instance_of(Dokku::Acl).to receive(:grant_team_apps).once
    described_class.perform_now(key.id, user.id, action: :add)
  end

  it "remove revokes ACLs and deletes key from all team servers" do
    expect_any_instance_of(Dokku::Acl).to receive(:revoke_all).once
    expect_any_instance_of(Dokku::SshKeys).to receive(:remove).with(
      "wokku-user-#{user.id}-key-#{key.id}"
    ).once
    described_class.perform_now(key.id, user.id, action: :remove)
  end

  it "add is a no-op when the key id cannot be found" do
    expect_any_instance_of(Dokku::SshKeys).not_to receive(:add)
    described_class.perform_now("00000000-0000-7000-8000-000000000000", user.id, action: :add)
  end

  it "returns early when user not found" do
    expect_any_instance_of(Dokku::SshKeys).not_to receive(:add)
    described_class.perform_now(key.id, "00000000-0000-7000-8000-000000000000", action: :add)
  end

  it "returns early when user has no team" do
    lonely = User.create!(email: "lonely@example.com", password: "password123456")
    lonely_key = lonely.ssh_public_keys.create!(name: "x", public_key: "ssh-rsa AA", fingerprint: "SHA256:zzz")
    expect_any_instance_of(Dokku::SshKeys).not_to receive(:add)
    described_class.perform_now(lonely_key.id, lonely.id, action: :add)
  end

  it "continues to next server when one raises" do
    allow_any_instance_of(Dokku::SshKeys).to receive(:add).and_raise(StandardError, "boom")
    expect { described_class.perform_now(key.id, user.id, action: :add) }.not_to raise_error
  end
end
