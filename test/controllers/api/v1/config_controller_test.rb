require "test_helper"

class Api::V1::ConfigControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "test@example.com", password: "password123456")
    @team = Team.create!(name: "Test Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
    @app_record = AppRecord.create!(name: "myapp", server: @server, team: @team, creator: @user)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "show returns config vars from Dokku" do
    mock_dokku(:show) do
      get api_v1_app_config_path(@app_record), headers: auth_headers
      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "postgres://localhost", body["config"]["DATABASE_URL"]
      assert_equal "redis://localhost", body["config"]["REDIS_URL"]
    end
  end

  test "destroy removes config vars" do
    @app_record.env_vars.create!(key: "OLD_VAR", value: "old")

    mock_dokku(:destroy) do
      delete api_v1_app_config_path(@app_record),
        params: { keys: [ "OLD_VAR" ] },
        headers: auth_headers
      assert_response :success
      assert_equal 0, @app_record.env_vars.count
    end
  end

  test "non-team member cannot access config" do
    other_user = User.create!(email: "other@example.com", password: "password123456")
    _, other_token = ApiToken.create_with_token!(user: other_user, name: "test")

    mock_dokku(:show) do
      get api_v1_app_config_path(@app_record),
        headers: { "Authorization" => "Bearer #{other_token}" }
      assert_response :forbidden
    end
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  def mock_dokku(action)
    mock_client = Object.new
    case action
    when :show
      mock_client.define_singleton_method(:run) { |cmd| "DATABASE_URL: postgres://localhost\nREDIS_URL: redis://localhost" }
    else
      mock_client.define_singleton_method(:run) { |cmd| "" }
    end

    original_new = Dokku::Client.method(:new)
    Dokku::Client.define_singleton_method(:new) { |*_args| mock_client }
    yield
  ensure
    Dokku::Client.define_singleton_method(:new, original_new)
  end
end
