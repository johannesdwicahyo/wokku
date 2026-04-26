require "test_helper"

class Dashboard::SshKeysControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # A real ed25519 public key — valid format so the Net::SSH fingerprinter
  # accepts it. Generated for testing only, no private half exists.
  VALID_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICaSt4kR8EbXWQsKqmJKlX5Fz48DGlhh3u6H3CoRnPpL test@example"

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "create adds an ssh key" do
    assert_difference "@user.ssh_public_keys.count", 1 do
      post dashboard_ssh_keys_path, params: {
        ssh_public_key: { name: "laptop", public_key: VALID_KEY }
      }
    end
    assert_response :success
  end

  test "create re-renders with errors when the key is invalid" do
    assert_no_difference "@user.ssh_public_keys.count" do
      post dashboard_ssh_keys_path, params: {
        ssh_public_key: { name: "bad", public_key: "not a real key" }
      }
    end
    assert_response :success
    assert_match(/not a valid SSH public key/i, response.body)
  end

  test "destroy removes the user's key" do
    key = @user.ssh_public_keys.create!(name: "rm", public_key: VALID_KEY)
    assert_difference "@user.ssh_public_keys.count", -1 do
      delete dashboard_ssh_key_path(key)
    end
    assert_response :success
  end

  test "destroy refuses keys that don't belong to the current user" do
    other = User.create!(email: "other-sshkey@example.com", password: "password123456")
    # Different valid key so fingerprint uniqueness doesn't collide with
    # the one used in the "destroy removes" test above.
    other_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGzTTfP+EfD99r8n4qYspR3gFXRW1HNBRlTjLXI+d7Dz other@example"
    key = other.ssh_public_keys.create!(name: "theirs", public_key: other_key)

    assert_no_difference "SshPublicKey.count" do
      delete dashboard_ssh_key_path(key)
    end
    assert key.reload.persisted?
  end
end
