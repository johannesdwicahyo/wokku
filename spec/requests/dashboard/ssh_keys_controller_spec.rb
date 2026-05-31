# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::SshKeys", type: :request do
  include Devise::Test::IntegrationHelpers

  # A real ed25519 public key — valid format so the Net::SSH fingerprinter
  # accepts it. Generated for testing only, no private half exists.
  VALID_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICaSt4kR8EbXWQsKqmJKlX5Fz48DGlhh3u6H3CoRnPpL test@example"

  let(:user) { users(:one) }

  before { sign_in user }

  it "create adds an ssh key" do
    expect {
      post dashboard_ssh_keys_path, params: {
        ssh_public_key: { name: "laptop", public_key: VALID_KEY }
      }
    }.to change { user.ssh_public_keys.count }.by(1)
    expect(response).to have_http_status(:success)
  end

  it "create re-renders with errors when the key is invalid" do
    expect {
      post dashboard_ssh_keys_path, params: {
        ssh_public_key: { name: "bad", public_key: "not a real key" }
      }
    }.not_to change { user.ssh_public_keys.count }
    expect(response).to have_http_status(:success)
    expect(response.body).to match(/not a valid SSH public key/i)
  end

  it "destroy removes the user's key" do
    key = user.ssh_public_keys.create!(name: "rm", public_key: VALID_KEY)
    expect {
      delete dashboard_ssh_key_path(key)
    }.to change { user.ssh_public_keys.count }.by(-1)
    expect(response).to have_http_status(:success)
  end

  it "destroy refuses keys that don't belong to the current user" do
    other = User.create!(email: "other-sshkey@example.com", password: "password123456")
    other_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGzTTfP+EfD99r8n4qYspR3gFXRW1HNBRlTjLXI+d7Dz other@example"
    key = other.ssh_public_keys.create!(name: "theirs", public_key: other_key)

    expect {
      delete dashboard_ssh_key_path(key)
    }.not_to change { SshPublicKey.count }
    expect(key.reload).to be_persisted
  end
end
