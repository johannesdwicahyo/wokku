require "test_helper"

class Api::V1::AddonsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "addons-test@example.com", password: "password123456")
    @team = Team.create!(name: "Addons Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
    @app_record = AppRecord.create!(name: "myapp", server: @server, team: @team, creator: @user)
    @database = DatabaseService.create!(name: "mydb", service_type: "postgres", server: @server)
    @app_record.app_databases.create!(database_service: @database, alias_name: "DATABASE")
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  # Auth tests
  test "index returns 401 without token" do
    get api_v1_app_addons_path(@app_record)
    assert_response :unauthorized
  end

  # Authenticated tests
  test "index returns app addons" do
    get api_v1_app_addons_path(@app_record), headers: auth_headers
    assert_response :success
    addons = JSON.parse(response.body)
    assert_kind_of Array, addons
    assert_equal 1, addons.length
    assert_equal "mydb", addons.first["name"]
    assert_equal "postgres", addons.first["service_type"]
  end

  test "index returns empty array when no addons" do
    other_app = AppRecord.create!(name: "emptyapp", server: @server, team: @team, creator: @user)
    get api_v1_app_addons_path(other_app), headers: auth_headers
    assert_response :success
    addons = JSON.parse(response.body)
    assert_equal [], addons
  end

  test "non-team member cannot access addons" do
    other_user = User.create!(email: "other-addons@example.com", password: "password123456")
    _, other_token = ApiToken.create_with_token!(user: other_user, name: "test")
    get api_v1_app_addons_path(@app_record), headers: { "Authorization" => "Bearer #{other_token}" }
    assert_response :forbidden
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
