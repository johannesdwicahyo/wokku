require "test_helper"

class Api::V1::LogDrainsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @app = app_records(:one)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
    Dokku::LogDrains.any_instance.stubs(:add).returns(nil)
    Dokku::LogDrains.any_instance.stubs(:remove).returns(nil)
  end

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  test "index lists existing drains" do
    @app.log_drains.create!(url: "https://example.com/logs", drain_type: "https")

    get "/api/v1/apps/#{@app.id}/log_drains", headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert body.length >= 1
  end

  test "create adds a new drain" do
    assert_difference "@app.log_drains.count", 1 do
      post "/api/v1/apps/#{@app.id}/log_drains",
        params: { url: "https://example.com/logs", drain_type: "https" },
        headers: auth_headers
    end
    assert_response :created
  end

  test "create rejects invalid params" do
    post "/api/v1/apps/#{@app.id}/log_drains",
      params: { url: "not-a-url", drain_type: "unknown" },
      headers: auth_headers
    assert_response :unprocessable_entity
  end

  test "create returns 503 on Dokku connection error" do
    Dokku::LogDrains.any_instance.stubs(:add).raises(Dokku::Client::ConnectionError, "ssh down")
    post "/api/v1/apps/#{@app.id}/log_drains",
      params: { url: "https://example.com/logs", drain_type: "https" },
      headers: auth_headers
    assert_response :service_unavailable
  end

  test "destroy removes the drain" do
    drain = @app.log_drains.create!(url: "https://example.com/logs", drain_type: "https")
    assert_difference "@app.log_drains.count", -1 do
      delete "/api/v1/apps/#{@app.id}/log_drains/#{drain.id}", headers: auth_headers
    end
    assert_response :success
  end

  test "destroy returns 503 on Dokku connection error" do
    drain = @app.log_drains.create!(url: "https://example.com/logs", drain_type: "https")
    Dokku::LogDrains.any_instance.stubs(:remove).raises(Dokku::Client::ConnectionError, "ssh down")
    delete "/api/v1/apps/#{@app.id}/log_drains/#{drain.id}", headers: auth_headers
    assert_response :service_unavailable
  end
end
