require "test_helper"

class Api::V1::AuthControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
    @token, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "login returns token" do
    post api_v1_auth_login_path, params: { email: @user.email, password: "password123456" }
    assert_response :created
    assert_not_nil JSON.parse(response.body)["token"]
  end

  test "login rejects bad password" do
    post api_v1_auth_login_path, params: { email: @user.email, password: "wrong" }
    assert_response :unauthorized
  end

  test "whoami returns current user" do
    get api_v1_auth_whoami_path, headers: auth_headers
    assert_response :success
    assert_equal @user.email, JSON.parse(response.body)["email"]
  end

  test "logout revokes token" do
    delete api_v1_auth_logout_path, headers: auth_headers
    assert_response :success
    assert @token.reload.revoked?
  end

  test "returns 401 without token" do
    get api_v1_auth_whoami_path
    assert_response :unauthorized
  end

  test "returns 401 with invalid token" do
    get api_v1_auth_whoami_path, headers: { "Authorization" => "Bearer invalid" }
    assert_response :unauthorized
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
