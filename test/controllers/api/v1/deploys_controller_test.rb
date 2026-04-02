require "test_helper"

class Api::V1::DeploysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "deploys-test@example.com", password: "password123456")
    @team = Team.create!(name: "Deploys Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
    @app_record = AppRecord.create!(name: "myapp", server: @server, team: @team, creator: @user)
    @deploy = Deploy.create!(app_record: @app_record, status: :succeeded, commit_sha: "abc1234")
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  # Auth tests
  test "index returns 401 without token" do
    get api_v1_app_deploys_path(@app_record)
    assert_response :unauthorized
  end

  test "show returns 401 without token" do
    get api_v1_app_deploy_path(@app_record, @deploy)
    assert_response :unauthorized
  end

  # Authenticated tests
  test "index returns deploys for app" do
    get api_v1_app_deploys_path(@app_record), headers: auth_headers
    assert_response :success
    deploys = JSON.parse(response.body)
    assert_kind_of Array, deploys
    assert_equal 1, deploys.length
    assert_equal "succeeded", deploys.first["status"]
  end

  test "show returns deploy details" do
    get api_v1_app_deploy_path(@app_record, @deploy), headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @deploy.id, body["id"]
    assert_equal "succeeded", body["status"]
    assert_equal "abc1234", body["commit_sha"]
  end

  test "non-team member cannot list deploys" do
    other_user = User.create!(email: "other-deploys@example.com", password: "password123456")
    _, other_token = ApiToken.create_with_token!(user: other_user, name: "test")
    get api_v1_app_deploys_path(@app_record), headers: { "Authorization" => "Bearer #{other_token}" }
    assert_response :forbidden
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
