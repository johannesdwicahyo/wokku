require "test_helper"

class Api::V1::ChecksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @app = app_records(:one)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
    Dokku::Checks.any_instance.stubs(:report).returns("healthy")
    Dokku::Checks.any_instance.stubs(:enable).returns(nil)
    Dokku::Checks.any_instance.stubs(:disable).returns(nil)
    Dokku::Checks.any_instance.stubs(:set).returns(nil)
  end

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  test "show returns the checks report" do
    get "/api/v1/apps/#{@app.id}/checks", headers: auth_headers
    assert_response :success
    assert_equal "healthy", JSON.parse(response.body)["checks"]
  end

  test "show returns 503 on connection error" do
    Dokku::Checks.any_instance.stubs(:report).raises(Dokku::Client::ConnectionError, "ssh down")
    get "/api/v1/apps/#{@app.id}/checks", headers: auth_headers
    assert_response :service_unavailable
  end

  test "update enables checks when enabled=true" do
    Dokku::Checks.any_instance.expects(:enable).once
    put "/api/v1/apps/#{@app.id}/checks", params: { enabled: "true" }, headers: auth_headers
    assert_response :success
  end

  test "update disables checks when enabled=false" do
    Dokku::Checks.any_instance.expects(:disable).once
    put "/api/v1/apps/#{@app.id}/checks", params: { enabled: "false" }, headers: auth_headers
    assert_response :success
  end

  test "update sets CHECKS_WAIT / TIMEOUT / ATTEMPTS" do
    Dokku::Checks.any_instance.expects(:set).with(@app.name, "CHECKS_WAIT", "10").once
    Dokku::Checks.any_instance.expects(:set).with(@app.name, "CHECKS_TIMEOUT", "20").once
    Dokku::Checks.any_instance.expects(:set).with(@app.name, "CHECKS_ATTEMPTS", "3").once
    put "/api/v1/apps/#{@app.id}/checks",
      params: { wait: "10", timeout: "20", attempts: "3" },
      headers: auth_headers
    assert_response :success
  end

  test "update sets CHECKS_PATH when path param given" do
    Dokku::Checks.any_instance.expects(:set).with(@app.name, "CHECKS_PATH", "/health").once
    put "/api/v1/apps/#{@app.id}/checks", params: { path: "/health" }, headers: auth_headers
    assert_response :success
  end

  test "update returns 503 on connection error" do
    Dokku::Checks.any_instance.stubs(:enable).raises(Dokku::Client::ConnectionError, "ssh down")
    put "/api/v1/apps/#{@app.id}/checks", params: { enabled: "true" }, headers: auth_headers
    assert_response :service_unavailable
  end
end
