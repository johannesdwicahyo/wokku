require "test_helper"

class Api::V1::SshKeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  test "index returns user's keys" do
    @user.ssh_public_keys.create!(name: "laptop", public_key: "ssh-ed25519 AAAAFa user@host", fingerprint: "SHA256:aaa")
    get "/api/v1/ssh_keys", headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert body.any? { |k| k["name"] == "laptop" }
  end

  test "create returns 422 when public key is not valid" do
    post "/api/v1/ssh_keys",
      params: { name: "bogus", public_key: "not a real key" },
      headers: auth_headers
    assert_response :unprocessable_entity
  end

  test "create returns 422 on validation error" do
    post "/api/v1/ssh_keys",
      params: { name: "", public_key: "" },
      headers: auth_headers
    assert_response :unprocessable_entity
  end

  test "destroy removes a key" do
    k = @user.ssh_public_keys.create!(name: "delme", public_key: "ssh-ed25519 AAAAdel user@host", fingerprint: "SHA256:del")
    assert_difference "@user.ssh_public_keys.count", -1 do
      delete "/api/v1/ssh_keys/#{k.id}", headers: auth_headers
    end
    assert_response :success
  end
end
