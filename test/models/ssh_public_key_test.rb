require "test_helper"

class SshPublicKeyTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
  end

  test "validates presence of name and public_key" do
    key = SshPublicKey.new(user: @user)
    assert_not key.valid?
    assert_includes key.errors[:name], "can't be blank"
    assert_includes key.errors[:public_key], "can't be blank"
  end

  # A real ed25519 pubkey line used across the next few tests.
  PUBKEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIQBxHTfYQUaxG3PdBjzBJbWJ9+nCN7Q8MpYbMxj0aRo test@example.com"

  test "same user re-uploading their own key gets a self-dup message" do
    @user.ssh_public_keys.create!(name: "laptop", public_key: PUBKEY)
    dup = @user.ssh_public_keys.build(name: "laptop-again", public_key: PUBKEY)
    assert_not dup.valid?
    assert_includes dup.errors[:base].to_s, "already added this key"
  end

  test "different user uploading the same key gets a generic message (no account enumeration)" do
    @user.ssh_public_keys.create!(name: "laptop", public_key: PUBKEY)
    other = User.create!(email: "other@example.com", password: "password123456")
    dup = other.ssh_public_keys.build(name: "also-laptop", public_key: PUBKEY)
    assert_not dup.valid?
    combined = dup.errors[:base].to_s
    assert_includes combined, "multiple Wokku accounts"
    assert_includes combined, "/docs/apps/ssh-keys"
    # Must NOT leak that another account owns this key.
    assert_not_includes combined.downcase, "already"
    assert_not_includes combined.downcase, "taken"
  end
end
