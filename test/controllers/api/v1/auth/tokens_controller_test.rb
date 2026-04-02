require "test_helper"

class Api::V1::Auth::TokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "tokens-test@example.com", password: "password123456")
    @token, @plain_token = ApiToken.create_with_token!(user: @user, name: "test-token")
  end

  # Auth tests
  test "index returns 401 without token" do
    get api_v1_auth_tokens_path
    assert_response :unauthorized
  end

  test "create returns 401 without token" do
    post api_v1_auth_tokens_path, params: { name: "new-token" }
    assert_response :unauthorized
  end

  test "destroy returns 401 without token" do
    delete api_v1_auth_token_path(@token)
    assert_response :unauthorized
  end

  # Authenticated tests
  test "index returns active tokens for current user" do
    get api_v1_auth_tokens_path, headers: auth_headers
    assert_response :success
    tokens = JSON.parse(response.body)
    assert_kind_of Array, tokens
    assert_equal 1, tokens.length
    assert_equal "test-token", tokens.first["name"]
  end

  test "create generates a new API token" do
    post api_v1_auth_tokens_path,
      params: { name: "my-new-token" },
      headers: auth_headers
    assert_response :created
    body = JSON.parse(response.body)
    assert body.key?("token")
    assert_equal "my-new-token", body["name"]
    assert body["id"].present?
  end

  test "create generates token with default name when name not provided" do
    post api_v1_auth_tokens_path, headers: auth_headers
    assert_response :created
    body = JSON.parse(response.body)
    assert body.key?("token")
    assert body["name"].present?
  end

  test "destroy revokes a token" do
    _, other_plain = ApiToken.create_with_token!(user: @user, name: "to-revoke")
    other_token = @user.api_tokens.find_by(name: "to-revoke")
    delete api_v1_auth_token_path(other_token), headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Token revoked", body["message"]
    assert other_token.reload.revoked?
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
