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

  # --- index ---

  test "index returns user's apps" do
    get api_v1_apps_path, headers: auth_headers
    assert_response :success
    apps = JSON.parse(response.body)
    assert_equal 1, apps.length
    assert_equal "myapp", apps.first["name"]
  end

  test "index returns 401 without token" do
    get api_v1_apps_path
    assert_response :unauthorized
  end

  # --- show ---

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

  test "show returns 401 without token" do
    get api_v1_app_path(@app_record)
    assert_response :unauthorized
  end

  test "show returns 404 for nonexistent app" do
    get api_v1_app_path(id: 999999), headers: auth_headers
    assert_response :not_found
  end

  # --- create ---

  test "create returns 401 without token" do
    post api_v1_apps_path, params: { name: "newapp", server_id: @server.id }
    assert_response :unauthorized
  end

  test "create succeeds with valid params and stubbed dokku" do
    stub_dokku_apps_create do
      post api_v1_apps_path,
           params: { name: "newapp", server_id: @server.id },
           headers: auth_headers
    end
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "newapp", body["name"]
  end

  test "create returns 403 when user is not team member of server's team" do
    other_team = Team.create!(name: "Other Team", owner: @user)
    other_server = Server.create!(name: "other", host: "9.9.9.9", team: other_team)
    # @user is NOT a member of other_team
    stub_dokku_apps_create do
      post api_v1_apps_path,
           params: { name: "blocked-app", server_id: other_server.id },
           headers: auth_headers
    end
    assert_includes [ 403, 422 ], response.status
  end

  test "create returns 503 on Dokku::Client::ConnectionError" do
    Dokku::Apps.define_method(:create) { |*| raise Dokku::Client::ConnectionError, "refused" }
    post api_v1_apps_path,
         params: { name: "connfail", server_id: @server.id },
         headers: auth_headers
    assert_response :service_unavailable
    body = JSON.parse(response.body)
    assert_match "Cannot connect", body["error"]
  end

  test "create returns 422 on Dokku::Client::CommandError" do
    Dokku::Apps.define_method(:create) { |*| raise Dokku::Client::CommandError, "app exists" }
    post api_v1_apps_path,
         params: { name: "cmderr", server_id: @server.id },
         headers: auth_headers
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "app exists", body["error"]
  end

  # --- update ---

  test "update returns 401 without token" do
    patch api_v1_app_path(@app_record), params: { deploy_branch: "develop" }
    assert_response :unauthorized
  end

  test "update changes deploy_branch without renaming when name unchanged" do
    stub_dokku_apps_create do # create stub not needed but ensure run doesn't fire
      patch api_v1_app_path(@app_record),
            params: { deploy_branch: "develop" },
            headers: auth_headers
    end
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "develop", body["deploy_branch"]
    assert_equal "develop", @app_record.reload.deploy_branch
  end

  test "update with new name calls Dokku rename" do
    rename_called = false
    Dokku::Apps.define_method(:rename) { |old, new_name| rename_called = true }
    patch api_v1_app_path(@app_record),
          params: { name: "renamed-app" },
          headers: auth_headers
    assert rename_called, "Expected Dokku::Apps#rename to be called"
    assert_response :success
  end

  test "update returns 422 on Dokku::Client::CommandError" do
    Dokku::Apps.define_method(:rename) { |*| raise Dokku::Client::CommandError, "rename failed" }
    patch api_v1_app_path(@app_record),
          params: { name: "bad-rename" },
          headers: auth_headers
    assert_response :unprocessable_entity
  end

  # --- destroy ---

  test "destroy returns 401 without token" do
    delete api_v1_app_path(@app_record)
    assert_response :unauthorized
  end

  test "destroy succeeds with stubbed dokku" do
    Dokku::Apps.define_method(:destroy) { |*| nil }
    assert_difference "AppRecord.count", -1 do
      delete api_v1_app_path(@app_record), headers: auth_headers
    end
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "App destroyed", body["message"]
  end

  test "destroy returns 503 on ConnectionError" do
    Dokku::Apps.define_method(:destroy) { |*| raise Dokku::Client::ConnectionError, "no route" }
    delete api_v1_app_path(@app_record), headers: auth_headers
    assert_response :service_unavailable
  end

  test "destroy returns 403 for non-admin team member" do
    member_user = User.create!(email: "member@example.com", password: "password123456")
    TeamMembership.create!(user: member_user, team: @team, role: :member)
    _, member_token = ApiToken.create_with_token!(user: member_user, name: "member")
    Dokku::Apps.define_method(:destroy) { |*| nil }
    delete api_v1_app_path(@app_record), headers: { "Authorization" => "Bearer #{member_token}" }
    assert_response :forbidden
  end

  # --- restart / stop / start ---

  test "restart returns 401 without token" do
    post restart_api_v1_app_path(@app_record)
    assert_response :unauthorized
  end

  test "restart succeeds with stubbed dokku" do
    Dokku::Processes.define_method(:restart) { |*| nil }
    post restart_api_v1_app_path(@app_record), headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_match "restart", body["message"]
  end

  test "restart returns 503 on ConnectionError" do
    Dokku::Processes.define_method(:restart) { |*| raise Dokku::Client::ConnectionError, "ssh failed" }
    post restart_api_v1_app_path(@app_record), headers: auth_headers
    assert_response :service_unavailable
  end

  test "stop succeeds with stubbed dokku" do
    Dokku::Processes.define_method(:stop) { |*| nil }
    post stop_api_v1_app_path(@app_record), headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_match "stop", body["message"]
  end

  test "start succeeds with stubbed dokku" do
    Dokku::Processes.define_method(:start) { |*| nil }
    post start_api_v1_app_path(@app_record), headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_match "start", body["message"]
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  def stub_dokku_apps_create(&block)
    original = Dokku::Apps.instance_method(:create)
    Dokku::Apps.define_method(:create) { |*| nil }
    block.call
  ensure
    Dokku::Apps.define_method(:create, original)
  end
end
