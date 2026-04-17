require "test_helper"

class Api::V1::AddonsControllerDeepTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @app = app_records(:one)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
    Dokku::Databases.any_instance.stubs(:create).returns(nil)
    Dokku::Databases.any_instance.stubs(:link).returns(nil)
    Dokku::Databases.any_instance.stubs(:unlink).returns(nil)
    Dokku::Databases.any_instance.stubs(:destroy).returns(nil)
  end

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  test "index lists existing addons" do
    db = @app.server.database_services.create!(name: "myapp-postgres", service_type: "postgres", status: :running)
    @app.app_databases.create!(database_service: db, alias_name: "DATABASE")

    get "/api/v1/apps/#{@app.id}/addons", headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert body.any? { |a| a["service_type"] == "postgres" }
  end

  test "create provisions a new addon with default name" do
    post "/api/v1/apps/#{@app.id}/addons",
      params: { service_type: "postgres" },
      headers: auth_headers
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "postgres", body["service_type"]
    assert_equal "running", body["status"]
    assert_match(/-postgres$/, body["name"])
  end

  test "create uses given name" do
    post "/api/v1/apps/#{@app.id}/addons",
      params: { service_type: "redis", name: "custom-redis" },
      headers: auth_headers
    assert_response :created
    assert_equal "custom-redis", JSON.parse(response.body)["name"]
  end

  test "create returns 422 when Dokku errors out" do
    Dokku::Databases.any_instance.stubs(:create).raises(Dokku::Client::CommandError.new("exists"))
    post "/api/v1/apps/#{@app.id}/addons",
      params: { service_type: "postgres" },
      headers: auth_headers
    assert_response :unprocessable_entity
  end
end
