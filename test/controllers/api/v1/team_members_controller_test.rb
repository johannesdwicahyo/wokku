require "test_helper"

class Api::V1::TeamMembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @team = teams(:one)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  test "index returns team memberships" do
    get "/api/v1/teams/#{@team.id}/members", headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert body.any? { |m| m["email"] == @user.email }
  end

  test "create adds an existing user as team member" do
    new_user = User.create!(email: "newmember@example.com", password: "password123456")
    assert_difference "@team.team_memberships.count", 1 do
      post "/api/v1/teams/#{@team.id}/members",
        params: { email: new_user.email, role: "member" },
        headers: auth_headers
    end
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal new_user.email, body["email"]
    assert_equal "member", body["role"]
  end

  test "create returns 404 when user email does not exist" do
    post "/api/v1/teams/#{@team.id}/members",
      params: { email: "nobody@example.com", role: "member" },
      headers: auth_headers
    assert_response :not_found
  end

  test "create returns 422 when membership invalid (duplicate)" do
    post "/api/v1/teams/#{@team.id}/members",
      params: { email: @user.email, role: "member" },
      headers: auth_headers
    assert_response :unprocessable_entity
  end

  test "destroy removes a team membership" do
    new_user = User.create!(email: "drop@example.com", password: "password123456")
    tm = TeamMembership.create!(user: new_user, team: @team, role: :member)

    assert_difference "@team.team_memberships.count", -1 do
      delete "/api/v1/teams/#{@team.id}/members/#{tm.id}", headers: auth_headers
    end
    assert_response :success
  end
end
