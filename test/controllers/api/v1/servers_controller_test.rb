require "test_helper"

class Api::V1::ServersControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Platform servers model: only system admins can list, view, add, or
    # destroy servers. Regular users still pick a deploy target via the
    # app-creation flow, which goes through Pundit scope, not this API.
    @admin = users(:admin)
    @user  = User.create!(email: "api-servers-test@example.com", password: "password123456")
    @server = Server.create!(name: "prod-api-test", host: "1.2.3.4")
    _, @admin_token = ApiToken.create_with_token!(user: @admin, name: "test-admin")
    _, @user_token  = ApiToken.create_with_token!(user: @user,  name: "test-user")
  end

  def admin_headers; { "Authorization" => "Bearer #{@admin_token}" }; end
  def user_headers;  { "Authorization" => "Bearer #{@user_token}" };  end

  test "index returns all platform servers to admins" do
    get api_v1_servers_path, headers: admin_headers
    assert_response :success
    names = JSON.parse(response.body).map { |s| s["name"] }
    assert_includes names, "prod-api-test"
  end

  test "index returns servers to non-admin so CLI can pick a deploy target" do
    get api_v1_servers_path, headers: user_headers
    assert_response :success
    names = JSON.parse(response.body).map { |s| s["name"] }
    assert_includes names, "prod-api-test"
  end

  test "show returns server details to admins" do
    get api_v1_server_path(@server), headers: admin_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "prod-api-test", body["name"]
    assert_nil body["ssh_private_key"]
  end

  test "show returns server details to non-admin" do
    get api_v1_server_path(@server), headers: user_headers
    assert_response :success
    assert_equal "prod-api-test", JSON.parse(response.body)["name"]
  end

  test "create succeeds for system admin" do
    post api_v1_servers_path,
      params: { name: "staging-api-test", host: "5.6.7.8" },
      headers: admin_headers
    assert_response :created
    assert_equal "staging-api-test", JSON.parse(response.body)["name"]
  end

  test "create forbidden for non-admin" do
    post api_v1_servers_path,
      params: { name: "rogue", host: "9.9.9.9" },
      headers: user_headers
    assert_response :forbidden
  end

  test "destroy succeeds for system admin" do
    delete api_v1_server_path(@server), headers: admin_headers
    assert_response :success
    assert_not Server.exists?(@server.id)
  end

  test "destroy forbidden for non-admin" do
    delete api_v1_server_path(@server), headers: user_headers
    assert_response :forbidden
    assert Server.exists?(@server.id)
  end
end
