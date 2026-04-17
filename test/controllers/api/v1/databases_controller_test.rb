require "test_helper"

class Api::V1::DatabasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(stripe_payment_method_id: "pm_test")
    @team = teams(:one)
    @server = servers(:one)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")

    Dokku::Databases.any_instance.stubs(:create).returns(nil)
    Dokku::Databases.any_instance.stubs(:destroy).returns(nil)
  end

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  test "index returns team-scoped databases" do
    @server.database_services.create!(name: "pg1", service_type: "postgres", status: :running)
    get "/api/v1/databases", headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert body.any? { |d| d["name"] == "pg1" }
  end

  test "show returns a specific database" do
    db = @server.database_services.create!(name: "pg2", service_type: "postgres", status: :running)
    get "/api/v1/databases/#{db.id}", headers: auth_headers
    assert_response :success
    assert_equal "pg2", JSON.parse(response.body)["name"]
  end

  test "create provisions a new database" do
    assert_difference "@server.database_services.count", 1 do
      post "/api/v1/databases",
        params: { server_id: @server.id, name: "new-pg", service_type: "postgres" },
        headers: auth_headers
    end
    assert_response :created
  end

  test "create returns 503 on Dokku connection error" do
    Dokku::Databases.any_instance.stubs(:create).raises(Dokku::Client::ConnectionError, "ssh down")
    post "/api/v1/databases",
      params: { server_id: @server.id, name: "new-pg", service_type: "postgres" },
      headers: auth_headers
    assert_response :service_unavailable
  end

  test "create returns 422 on Dokku command error" do
    Dokku::Databases.any_instance.stubs(:create).raises(Dokku::Client::CommandError.new("duplicate"))
    post "/api/v1/databases",
      params: { server_id: @server.id, name: "new-pg", service_type: "postgres" },
      headers: auth_headers
    assert_response :unprocessable_entity
  end

  test "destroy tears down the database" do
    db = @server.database_services.create!(name: "goodbye", service_type: "postgres", status: :running)
    assert_difference "@server.database_services.count", -1 do
      delete "/api/v1/databases/#{db.id}", headers: auth_headers
    end
    assert_response :success
  end

  test "destroy returns 503 on Dokku connection error" do
    db = @server.database_services.create!(name: "err-down", service_type: "postgres", status: :running)
    Dokku::Databases.any_instance.stubs(:destroy).raises(Dokku::Client::ConnectionError, "ssh down")
    delete "/api/v1/databases/#{db.id}", headers: auth_headers
    assert_response :service_unavailable
  end

  test "link attaches a database to an app" do
    db = @server.database_services.create!(name: "shared-pg", service_type: "postgres", status: :running)
    app = app_records(:one)
    Dokku::Databases.any_instance.stubs(:link).returns(nil)

    assert_difference "AppDatabase.count", 1 do
      post "/api/v1/databases/#{db.id}/link", params: { app_id: app.id }, headers: auth_headers
    end
    assert_response :created
  end

  test "link returns 503 on connection error" do
    db = @server.database_services.create!(name: "link-err", service_type: "postgres", status: :running)
    Dokku::Databases.any_instance.stubs(:link).raises(Dokku::Client::ConnectionError, "ssh down")
    post "/api/v1/databases/#{db.id}/link",
      params: { app_id: app_records(:one).id },
      headers: auth_headers
    assert_response :service_unavailable
  end

  test "unlink detaches a database from an app" do
    db = @server.database_services.create!(name: "unlink-pg", service_type: "postgres", status: :running)
    app = app_records(:one)
    AppDatabase.create!(app_record: app, database_service: db, alias_name: "DB")

    Dokku::Databases.any_instance.stubs(:unlink).returns(nil)

    assert_difference "AppDatabase.count", -1 do
      post "/api/v1/databases/#{db.id}/unlink", params: { app_id: app.id }, headers: auth_headers
    end
    assert_response :success
  end
end
