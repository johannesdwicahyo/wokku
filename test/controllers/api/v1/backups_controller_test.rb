require "test_helper"

class Api::V1::BackupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "backups-test@example.com", password: "password123456")
    @team = Team.create!(name: "Backups Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
    @database = DatabaseService.create!(name: "mydb", service_type: "postgres", server: @server)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  # Auth tests
  test "index returns 401 without token" do
    get api_v1_database_backups_path(@database)
    assert_response :unauthorized
  end

  test "create returns 401 without token" do
    post api_v1_database_backups_path(@database)
    assert_response :unauthorized
  end

  # Authenticated tests
  test "index returns empty list when no backups" do
    get api_v1_database_backups_path(@database), headers: auth_headers
    assert_response :success
    backups = JSON.parse(response.body)
    assert_equal [], backups
  end

  test "non-team member cannot list backups" do
    other_user = User.create!(email: "other-backups@example.com", password: "password123456")
    _, other_token = ApiToken.create_with_token!(user: other_user, name: "test")
    get api_v1_database_backups_path(@database), headers: { "Authorization" => "Bearer #{other_token}" }
    assert_response :forbidden
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
