require "test_helper"

class Api::V1::ServersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
    @team = Team.create!(name: "Test Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "index returns user's servers" do
    get api_v1_servers_path, headers: auth_headers
    assert_response :success
    servers = JSON.parse(response.body)
    assert_equal 1, servers.length
    assert_equal "prod", servers.first["name"]
  end

  test "show returns server details" do
    get api_v1_server_path(@server), headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "prod", body["name"]
    assert_nil body["ssh_private_key"]
  end

  test "create adds server" do
    post api_v1_servers_path,
      params: { team_id: @team.id, name: "staging", host: "5.6.7.8" },
      headers: auth_headers
    assert_response :created
    assert_equal "staging", JSON.parse(response.body)["name"]
  end

  test "destroy removes server" do
    delete api_v1_server_path(@server), headers: auth_headers
    assert_response :success
    assert_not Server.exists?(@server.id)
  end

  test "non-team member cannot show server" do
    other_user = User.create!(email: "other@example.com", password: "password123456")
    _, other_token = ApiToken.create_with_token!(user: other_user, name: "test")
    get api_v1_server_path(@server), headers: { "Authorization" => "Bearer #{other_token}" }
    assert_response :forbidden
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
