require "rails_helper"

RSpec.describe SshPublicKey do
  let(:user) { User.create!(email: "ssh-test@example.com", password: "password123456") }

  PUBKEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIQBxHTfYQUaxG3PdBjzBJbWJ9+nCN7Q8MpYbMxj0aRo test@example.com"

  it "validates presence of name and public_key" do
    key = SshPublicKey.new(user: user)
    expect(key).not_to be_valid
    expect(key.errors[:name]).to include("can't be blank")
    expect(key.errors[:public_key]).to include("can't be blank")
  end

  it "same user re-uploading their own key gets a self-dup message" do
    user.ssh_public_keys.create!(name: "laptop", public_key: PUBKEY)
    dup = user.ssh_public_keys.build(name: "laptop-again", public_key: PUBKEY)
    expect(dup).not_to be_valid
    expect(dup.errors[:base].to_s).to include("already added this key")
  end

  it "different user uploading the same key gets a generic message (no account enumeration)" do
    user.ssh_public_keys.create!(name: "laptop", public_key: PUBKEY)
    other = User.create!(email: "other-ssh@example.com", password: "password123456")
    dup = other.ssh_public_keys.build(name: "also-laptop", public_key: PUBKEY)
    expect(dup).not_to be_valid
    combined = dup.errors[:base].to_s
    expect(combined).to include("multiple Wokku accounts")
    expect(combined).to include("/docs/apps/ssh-keys")
    expect(combined.downcase).not_to include("already")
    expect(combined.downcase).not_to include("taken")
  end
end
