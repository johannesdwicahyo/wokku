require "test_helper"

class Api::V1::AppsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
    @team = Team.create!(name: "Test Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
    @app_record = AppRecord.create!(name: "myapp", server: @server, team: @team, creator: @user)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "index returns user's apps" do
    get api_v1_apps_path, headers: auth_headers
    assert_response :success
    apps = JSON.parse(response.body)
    assert_equal 1, apps.length
    assert_equal "myapp", apps.first["name"]
  end

  test "show returns app details" do
    get api_v1_app_path(@app_record), headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "myapp", body["name"]
  end

  test "non-team member cannot show app" do
    other_user = User.create!(email: "other@example.com", password: "password123456")
    _, other_token = ApiToken.create_with_token!(user: other_user, name: "test")
    get api_v1_app_path(@app_record), headers: { "Authorization" => "Bearer #{other_token}" }
    assert_response :forbidden
  end

  test "index returns 401 without token" do
    get api_v1_apps_path
    assert_response :unauthorized
  end

  test "show returns 401 without token" do
    get api_v1_app_path(@app_record)
    assert_response :unauthorized
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
