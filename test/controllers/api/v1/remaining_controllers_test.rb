require "test_helper"

class Api::V1::DomainsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "domains-test@example.com", password: "password123456")
    @team = Team.create!(name: "Domains Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
    @app_record = AppRecord.create!(name: "myapp", server: @server, team: @team, creator: @user)
    @domain = Domain.create!(hostname: "myapp.example.com", app_record: @app_record)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "index returns domains for app" do
    get api_v1_app_domains_path(@app_record), headers: auth_headers
    assert_response :success
    domains = JSON.parse(response.body)
    assert_equal 1, domains.length
    assert_equal "myapp.example.com", domains.first["hostname"]
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end

class Api::V1::DatabasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "db-test@example.com", password: "password123456")
    @team = Team.create!(name: "DB Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
    @database = DatabaseService.create!(name: "mydb", service_type: "postgres", server: @server)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "index returns user's databases" do
    get api_v1_databases_path, headers: auth_headers
    assert_response :success
    dbs = JSON.parse(response.body)
    assert_equal 1, dbs.length
    assert_equal "mydb", dbs.first["name"]
  end

  test "show returns database details" do
    get api_v1_database_path(@database), headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "postgres", body["service_type"]
  end

  test "index returns 401 without token" do
    get api_v1_databases_path
    assert_response :unauthorized
  end

  test "show returns 401 without token" do
    get api_v1_database_path(@database)
    assert_response :unauthorized
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end

class Api::V1::ReleasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "releases-test@example.com", password: "password123456")
    @team = Team.create!(name: "Releases Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
    @app_record = AppRecord.create!(name: "myapp", server: @server, team: @team, creator: @user)
    @release = Release.create!(app_record: @app_record, description: "Initial release")
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "index returns releases for app" do
    get api_v1_app_releases_path(@app_record), headers: auth_headers
    assert_response :success
    releases = JSON.parse(response.body)
    assert_equal 1, releases.length
  end

  test "show returns release details" do
    get api_v1_app_release_path(@app_record, @release), headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["version"]
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end

class Api::V1::SshKeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "ssh-test@example.com", password: "password123456")
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "index returns user's ssh keys" do
    get api_v1_ssh_keys_path, headers: auth_headers
    assert_response :success
    assert_equal [], JSON.parse(response.body)
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end

class Api::V1::TeamsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "teams-test@example.com", password: "password123456")
    @team = Team.create!(name: "My Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "index returns user's teams" do
    get api_v1_teams_path, headers: auth_headers
    assert_response :success
    teams = JSON.parse(response.body)
    assert_equal 1, teams.length
    assert_equal "My Team", teams.first["name"]
  end

  test "create creates a new team" do
    post api_v1_teams_path, params: { name: "New Team" }, headers: auth_headers
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "New Team", body["name"]
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end

class Api::V1::TeamMembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "tm-test@example.com", password: "password123456")
    @team = Team.create!(name: "Members Team", owner: @user)
    @membership = TeamMembership.create!(user: @user, team: @team, role: :admin)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "index returns team members" do
    get api_v1_team_members_path(@team), headers: auth_headers
    assert_response :success
    members = JSON.parse(response.body)
    assert_equal 1, members.length
    assert_equal @user.email, members.first["email"]
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end

class Api::V1::NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "notif-test@example.com", password: "password123456")
    @team = Team.create!(name: "Notif Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @notification = Notification.create!(
      team: @team,
      channel: :email,
      events: [ "deploy" ],
      config: { email: "alert@example.com" }
    )
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "index returns user's notifications" do
    get api_v1_notifications_path, headers: auth_headers
    assert_response :success
    notifications = JSON.parse(response.body)
    assert_equal 1, notifications.length
  end

  test "destroy removes notification" do
    delete api_v1_notification_path(@notification), headers: auth_headers
    assert_response :success
    assert_not Notification.exists?(@notification.id)
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end

class Api::V1::PsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "ps-test@example.com", password: "password123456")
    @team = Team.create!(name: "PS Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
    @app_record = AppRecord.create!(name: "myapp", server: @server, team: @team, creator: @user)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "show returns process info" do
    mock_client = Object.new
    mock_client.define_singleton_method(:run) { |cmd| "Deployed: true\nRestore: true" }

    original_new = Dokku::Client.method(:new)
    Dokku::Client.define_singleton_method(:new) { |*_args| mock_client }

    get api_v1_app_ps_path(@app_record), headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("processes")
  ensure
    Dokku::Client.define_singleton_method(:new, original_new)
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end

class Api::V1::LogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "logs-test@example.com", password: "password123456")
    @team = Team.create!(name: "Logs Team", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
    @server = Server.create!(name: "prod", host: "1.2.3.4", team: @team)
    @app_record = AppRecord.create!(name: "myapp", server: @server, team: @team, creator: @user)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  test "index returns app logs" do
    mock_client = Object.new
    mock_client.define_singleton_method(:run) { |cmd| "2026-03-13 log line 1\n2026-03-13 log line 2" }

    original_new = Dokku::Client.method(:new)
    Dokku::Client.define_singleton_method(:new) { |*_args| mock_client }

    get api_v1_app_logs_path(@app_record), headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("logs")
  ensure
    Dokku::Client.define_singleton_method(:new, original_new)
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end
end
